/**
 * Documents: signed upload URL, post-upload record, list, download-url, delete.
 * The plaintext content never traverses the server — only the encrypted blob in
 * MinIO does. The server stores nonce + tag for AES-GCM, plus the encrypted title.
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { randomBytes } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import { closeTestApp, getTestApp } from './helpers/app.js';
import {
  makePool,
  resetDb,
  insertUser,
  insertCircle,
  type SeededCircle,
  type SeededUser,
} from './helpers/db.js';
import { bearer, loginAs } from './helpers/auth.js';

describe('Documents', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let owner: SeededUser;
  let circle: SeededCircle;
  let token: string;

  beforeAll(async () => {
    app = await getTestApp();
    pool = makePool();
  });
  afterAll(async () => {
    await closeTestApp();
    await pool.end();
  });
  beforeEach(async () => {
    await resetDb(pool);
    owner = await insertUser(pool, { appleId: 'mock|doc-owner' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Doc Circle' });
    token = (await loginAs(app, owner.appleId)).accessToken;
  });

  it('upload-url returns a signed PUT URL for cc-documents', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/documents/upload-url`,
      headers: bearer(token),
      payload: {
        bucket: 'cc-documents',
        contentType: 'application/pdf',
        sizeBytes: 245_678,
        filename: 'insurance.pdf',
      },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { url: string; objectKey: string; bucket: string };
    expect(body.bucket).toBe('cc-documents');
    expect(body.objectKey).toContain(circle.id);
    expect(body.url).toMatch(/^https?:\/\//);
  });

  it('POST creates the row with encrypted title; GET returns it', async () => {
    const nonce = randomBytes(12).toString('base64');
    const tag = randomBytes(16).toString('base64');
    const objectKey = `${circle.id}/2026-05-13/${randomBytes(8).toString('hex')}-doc.pdf`;

    const create = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/documents`,
      headers: bearer(token),
      payload: {
        title: 'BCBS Insurance Card',
        documentType: 'insurance_card',
        objectKey,
        mimeType: 'application/pdf',
        sizeBytes: 245_678,
        encryptionNonce: nonce,
        encryptionTag: tag,
        issuedAt: '2026-01-01',
      },
    });
    expect(create.statusCode).toBe(201);
    const { id } = JSON.parse(create.body) as { id: string };

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/documents`,
      headers: bearer(token),
    });
    const body = JSON.parse(list.body) as {
      documents: Array<{
        id: string;
        title: string;
        documentType: string;
        sizeBytes: number;
        issuedAt: string | null;
      }>;
    };
    expect(body.documents).toHaveLength(1);
    expect(body.documents[0]!.id).toBe(id);
    expect(body.documents[0]!.title).toBe('BCBS Insurance Card');
    expect(body.documents[0]!.documentType).toBe('insurance_card');
    expect(body.documents[0]!.sizeBytes).toBe(245_678);
    expect(body.documents[0]!.issuedAt).toBe('2026-01-01');

    const dl = await app.inject({
      method: 'GET',
      url: `/v1/documents/${id}/download-url`,
      headers: bearer(token),
    });
    expect(dl.statusCode).toBe(200);
    const dlBody = JSON.parse(dl.body) as {
      url: string;
      encryptionNonce: string;
      encryptionTag: string;
    };
    expect(dlBody.url).toMatch(/^https?:\/\//);
    expect(dlBody.encryptionNonce).toBe(nonce);
    expect(dlBody.encryptionTag).toBe(tag);
  });

  it('returns 402 subscription_required for a free-tier circle', async () => {
    const freeCircle = await insertCircle(pool, {
      ownerId: owner.id,
      name: 'Free Circle',
      tier: 'free',
    });
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${freeCircle.id}/documents/upload-url`,
      headers: bearer(token),
      payload: { bucket: 'cc-documents', contentType: 'application/pdf', sizeBytes: 1024 },
    });
    expect(res.statusCode).toBe(402);
    expect(JSON.parse(res.body).error.code).toBe('subscription_required');
  });

  it('DELETE soft-deletes; only the uploader can delete', async () => {
    const other = await insertUser(pool, { appleId: 'mock|other-uploader' });
    await pool.query(
      `INSERT INTO circle_members (circle_id, user_id, role, status, display_name, joined_at)
       VALUES ($1, $2, 'family_member', 'active', 'Other', NOW())`,
      [circle.id, other.id],
    );
    const otherToken = (await loginAs(app, other.appleId)).accessToken;

    const nonce = randomBytes(12).toString('base64');
    const tag = randomBytes(16).toString('base64');
    const create = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/documents`,
      headers: bearer(token),
      payload: {
        title: 'Owned by owner',
        documentType: 'other',
        objectKey: `${circle.id}/2026-05-13/owner.pdf`,
        mimeType: 'application/pdf',
        sizeBytes: 1024,
        encryptionNonce: nonce,
        encryptionTag: tag,
      },
    });
    const id = JSON.parse(create.body).id as string;

    const wrong = await app.inject({
      method: 'DELETE',
      url: `/v1/documents/${id}`,
      headers: bearer(otherToken),
    });
    expect(wrong.statusCode).toBe(403);

    const right = await app.inject({
      method: 'DELETE',
      url: `/v1/documents/${id}`,
      headers: bearer(token),
    });
    expect(right.statusCode).toBe(204);
  });
});
