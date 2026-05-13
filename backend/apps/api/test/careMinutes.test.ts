/**
 * Care minutes: HCBS-coded billable time entries. Verifies duration auto-calc,
 * HCBS code validation, overlap-rejection, and export-pdf job queueing.
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
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

describe('Care minutes', () => {
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
    owner = await insertUser(pool, { appleId: 'mock|cm-owner' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Care-min Circle' });
    token = (await loginAs(app, owner.appleId)).accessToken;
  });

  it('creates a care-minute entry, computes duration, lists it back', async () => {
    const startedAt = '2026-05-13T08:00:00Z';
    const endedAt = '2026-05-13T10:30:00Z'; // 150 min
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/care-minutes`,
      headers: bearer(token),
      payload: {
        serviceCode: 'T1019',
        serviceDescription: 'Personal care services',
        startedAt,
        endedAt,
        notes: 'Bath + grooming + transferring',
        fiscalIntermediary: 'PPL',
      },
    });
    expect(res.statusCode).toBe(201);
    const body = JSON.parse(res.body) as { id: string; durationMinutes: number };
    expect(body.durationMinutes).toBe(150);

    const list = await app.inject({
      method: 'GET',
      url: `/v1/circles/${circle.id}/care-minutes`,
      headers: bearer(token),
    });
    const data = JSON.parse(list.body) as {
      entries: Array<{
        serviceCode: string;
        durationMinutes: number;
        notes: string | null;
        fiscalIntermediary: string | null;
      }>;
    };
    expect(data.entries).toHaveLength(1);
    expect(data.entries[0]!.serviceCode).toBe('T1019');
    expect(data.entries[0]!.durationMinutes).toBe(150);
    expect(data.entries[0]!.notes).toBe('Bath + grooming + transferring');
    expect(data.entries[0]!.fiscalIntermediary).toBe('PPL');
  });

  it('rejects an unknown HCBS service code', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/care-minutes`,
      headers: bearer(token),
      payload: {
        serviceCode: 'XX0000',
        serviceDescription: 'fake',
        startedAt: '2026-05-13T08:00:00Z',
        endedAt: '2026-05-13T10:00:00Z',
      },
    });
    expect(res.statusCode).toBe(422);
  });

  it('rejects overlapping entries from the same caregiver', async () => {
    const ok = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/care-minutes`,
      headers: bearer(token),
      payload: {
        serviceCode: 'T1019',
        serviceDescription: 'Personal care services',
        startedAt: '2026-05-13T08:00:00Z',
        endedAt: '2026-05-13T10:00:00Z',
      },
    });
    expect(ok.statusCode).toBe(201);

    const dup = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/care-minutes`,
      headers: bearer(token),
      payload: {
        serviceCode: 'T1019',
        serviceDescription: 'Personal care services',
        startedAt: '2026-05-13T09:00:00Z', // overlaps with the first
        endedAt: '2026-05-13T11:00:00Z',
      },
    });
    expect(dup.statusCode).toBe(409);
  });

  it('rejects endedAt before startedAt', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/care-minutes`,
      headers: bearer(token),
      payload: {
        serviceCode: 'T1019',
        serviceDescription: 'Personal care services',
        startedAt: '2026-05-13T10:00:00Z',
        endedAt: '2026-05-13T09:00:00Z',
      },
    });
    expect(res.statusCode).toBe(422);
  });

  it('export-pdf enqueues a job and returns 202 + jobId', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${circle.id}/care-minutes/export-pdf`,
      headers: bearer(token),
      payload: { startDate: '2026-05-01', endDate: '2026-05-31', fiscalIntermediary: 'PPL' },
    });
    expect(res.statusCode).toBe(202);
    const body = JSON.parse(res.body) as { jobId: string };
    expect(body.jobId).toBeTruthy();
  });
});
