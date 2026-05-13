import { Buffer } from 'node:buffer';
import PDFDocument from 'pdfkit';
import { Client as MinioClient } from 'minio';
import type pg from 'pg';
import { withRls } from '@carecircle/db';
import {
  decryptColumn,
  hcbsByCode,
  type Logger,
  unwrapDek,
} from '@carecircle/shared';
import type { Config } from '../config.js';
import type { PdfJobData } from '../queues.js';

type EntryRow = {
  id: string;
  service_code: string;
  service_description: string;
  started_at: Date;
  ended_at: Date;
  duration_minutes: number;
  notes_enc: Buffer | null;
  fiscal_intermediary: string | null;
};

type CaregiverRow = { display_name: string };
type CircleRow = { name: string; recipient_first_name_enc: Buffer | null };
type KeyRow = { encrypted_dek: Buffer };

function fmtRange(start: string, end: string): string {
  return `${new Date(start).toISOString().slice(0, 10)} → ${new Date(end).toISOString().slice(0, 10)}`;
}

function fmtClock(value: Date): string {
  return new Date(value).toISOString().replace('T', ' ').slice(0, 16) + 'Z';
}

export async function runPdfJob(
  data: PdfJobData,
  ctx: { pool: pg.Pool; config: Config; logger: Logger; minio: MinioClient },
): Promise<{ objectKey: string; entries: number; totalMinutes: number }> {
  const { pool, config, logger, minio } = ctx;
  if (data.jobType !== 'care_minutes_export') {
    throw new Error(`unsupported pdf job type: ${data.jobType}`);
  }
  const start = new Date(data.startDate);
  const end = new Date(data.endDate);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    throw new Error('invalid date range');
  }

  const { entries, caregiver, circle, dek } = await withRls(
    pool,
    { role: 'app_service' },
    async (client) => {
      const entryResult = await client.query<EntryRow>(
        `SELECT id, service_code, service_description, started_at, ended_at,
                duration_minutes, notes_enc, fiscal_intermediary
         FROM care_minute_entries
         WHERE circle_id = $1
           AND caregiver_user_id = $2
           AND started_at >= $3
           AND ended_at <= $4
           AND deleted_at IS NULL
         ORDER BY started_at ASC`,
        [data.circleId, data.caregiverUserId, start, end],
      );
      const caregiverResult = await client.query<CaregiverRow>(
        `SELECT display_name FROM circle_members
         WHERE circle_id = $1 AND user_id = $2 AND deleted_at IS NULL
         LIMIT 1`,
        [data.circleId, data.caregiverUserId],
      );
      const circleResult = await client.query<CircleRow>(
        `SELECT c.name AS name, cr.first_name_enc AS recipient_first_name_enc
         FROM circles c
         LEFT JOIN care_recipients cr ON cr.circle_id = c.id
         WHERE c.id = $1
         LIMIT 1`,
        [data.circleId],
      );
      const keyResult = await client.query<KeyRow>(
        `SELECT encrypted_dek FROM circle_keys WHERE circle_id = $1`,
        [data.circleId],
      );
      const wrapped = keyResult.rows[0]?.encrypted_dek;
      const dek = wrapped ? unwrapDek(wrapped, config.APP_MASTER_KEY) : null;
      return {
        entries: entryResult.rows,
        caregiver: caregiverResult.rows[0] ?? null,
        circle: circleResult.rows[0] ?? null,
        dek,
      };
    },
  );

  if (!circle) {
    throw new Error(`circle ${data.circleId} not found`);
  }
  const recipientName =
    circle.recipient_first_name_enc && dek
      ? decryptColumn(circle.recipient_first_name_enc, dek)
      : 'the Care Recipient';

  const doc = new PDFDocument({ size: 'LETTER', margin: 54 });
  const chunks: Buffer[] = [];
  doc.on('data', (chunk: Buffer) => chunks.push(chunk));
  const finished = new Promise<Buffer>((resolveBuf, rejectBuf) => {
    doc.on('end', () => resolveBuf(Buffer.concat(chunks)));
    doc.on('error', rejectBuf);
  });

  doc.fontSize(18).text('Care Minutes Report', { align: 'left' });
  doc.moveDown(0.2);
  doc.fontSize(10).fillColor('#555').text(`Circle: ${circle.name}`);
  doc.text(`Care Recipient: ${recipientName}`);
  doc.text(`Caregiver: ${caregiver?.display_name ?? data.caregiverUserId}`);
  doc.text(`Period: ${fmtRange(data.startDate, data.endDate)}`);
  if (data.fiscalIntermediary) {
    doc.text(`Fiscal Intermediary: ${data.fiscalIntermediary}`);
  }
  doc.text(`Generated: ${new Date().toISOString().replace('T', ' ').slice(0, 19)}Z`);
  doc.moveDown(0.6);
  doc.fillColor('#000');

  let totalMinutes = 0;
  doc.fontSize(11);
  for (const entry of entries) {
    const meta = hcbsByCode(entry.service_code);
    const description = meta?.description ?? entry.service_description;
    const notes =
      entry.notes_enc && dek ? decryptColumn(entry.notes_enc, dek).slice(0, 240) : null;
    doc.fontSize(11).fillColor('#000').text(`${fmtClock(entry.started_at)} → ${fmtClock(entry.ended_at)}`);
    doc.fontSize(10).fillColor('#444');
    doc.text(`  ${entry.service_code} · ${description}`);
    doc.text(`  Duration: ${entry.duration_minutes} min`);
    if (notes) {
      doc.text(`  Notes: ${notes}`);
    }
    doc.moveDown(0.4);
    totalMinutes += entry.duration_minutes;
  }

  doc.moveDown(0.4);
  doc.fontSize(12).fillColor('#000');
  doc.text(`Total entries: ${entries.length}`);
  doc.text(`Total minutes: ${totalMinutes}`);
  doc.moveDown(0.4);
  doc.fontSize(8).fillColor('#888');
  doc.text(
    'Not medical advice. This export records caregiving minutes and is not a billing claim. Submit to your fiscal intermediary per their procedures.',
  );

  doc.end();
  const buffer = await finished;
  const objectKey = `care-minutes/${data.circleId}/${data.caregiverUserId}/${Date.now()}.pdf`;
  await minio.putObject(config.PDF_BUCKET, objectKey, buffer, buffer.length, {
    'Content-Type': 'application/pdf',
  });
  await withRls(pool, { role: 'app_service' }, async (client) => {
    await client.query(
      `UPDATE care_minute_entries
       SET exported_at = NOW(), export_pdf_key = $1
       WHERE id = ANY($2::uuid[])`,
      [objectKey, entries.map((e) => e.id)],
    );
  });
  logger.info(
    { circleId: data.circleId, caregiverUserId: data.caregiverUserId, entries: entries.length, objectKey },
    'pdf export complete',
  );
  return { objectKey, entries: entries.length, totalMinutes };
}
