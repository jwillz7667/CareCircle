import type pg from 'pg';
import { withRls } from '@carecircle/db';
import type { Logger } from '@carecircle/shared';
import type { DigestJobData, PushJobData } from '../queues.js';
import type { Queue } from 'bullmq';

type ActivityRow = {
  activity_type: string;
  headline: string | null;
  occurred_at: Date;
};

export async function runDigestJob(
  data: DigestJobData,
  ctx: { pool: pg.Pool; logger: Logger; pushQueue: Queue<PushJobData> },
): Promise<{ recentCount: number; queued: boolean }> {
  const { pool, logger, pushQueue } = ctx;
  const since = new Date(Date.now() - 24 * 3600 * 1000);
  const recent = await withRls(pool, { role: 'app_service' }, async (client) => {
    const result = await client.query<ActivityRow>(
      `SELECT activity_type, headline, occurred_at
       FROM activities
       WHERE circle_id = $1
         AND occurred_at >= $2
         AND deleted_at IS NULL
       ORDER BY occurred_at DESC
       LIMIT 6`,
      [data.circleId, since],
    );
    return result.rows;
  });
  if (recent.length === 0) {
    return { recentCount: 0, queued: false };
  }
  const summary = recent
    .map((row) => row.headline ?? row.activity_type.replaceAll('_', ' '))
    .slice(0, 3)
    .join(' · ');
  const day = new Date().toISOString().slice(0, 10);
  await pushQueue.add(
    'digest',
    {
      userIds: [data.userId],
      circleId: data.circleId,
      alert: {
        title: 'CareCircle daily digest',
        body: `${recent.length} update${recent.length === 1 ? '' : 's'} in the past day: ${summary}`,
      },
      category: 'cc_digest',
    },
    // One digest per recipient per circle per day, even if the job re-runs.
    { jobId: `digest:${data.circleId}:${data.userId}:${day}` },
  );
  logger.info({ circleId: data.circleId, userId: data.userId, recent: recent.length }, 'digest queued');
  return { recentCount: recent.length, queued: true };
}
