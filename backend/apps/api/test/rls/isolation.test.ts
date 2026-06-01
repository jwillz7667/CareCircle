/**
 * Cross-circle RLS isolation suite. This is the single most important test
 * in the backend: every PHI-bearing path must refuse to serve data from a
 * circle the requester does not belong to.
 *
 * Strategy:
 *   - Seed two unrelated circles (Alice owns A, Bob owns B).
 *   - Insert PHI in B via a service-role direct DB connection.
 *   - As Alice (via /v1/auth/apple → bearer), hit every read + write path
 *     against B and assert 404 / 403 / empty.
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import { encryptColumn } from '@carecircle/shared';
import { closeTestApp, getTestApp } from '../helpers/app.js';
import {
  addMember,
  insertActivityRaw,
  insertCircle,
  insertMedicationRaw,
  insertUser,
  makePool,
  resetDb,
  type SeededCircle,
  type SeededUser,
} from '../helpers/db.js';
import { bearer, loginAs } from '../helpers/auth.js';

describe('RLS isolation', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let alice: SeededUser;
  let bob: SeededUser;
  let aliceCircle: SeededCircle;
  let bobCircle: SeededCircle;
  let aliceAccess: string;
  let bobAccess: string;

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
    alice = await insertUser(pool, { appleId: 'mock|alice', email: 'alice@test.example', displayName: 'Alice' });
    bob = await insertUser(pool, { appleId: 'mock|bob', email: 'bob@test.example', displayName: 'Bob' });
    aliceCircle = await insertCircle(pool, { ownerId: alice.id, name: "Alice's Circle" });
    bobCircle = await insertCircle(pool, { ownerId: bob.id, name: "Bob's Circle" });
    const aliceLogin = await loginAs(app, alice.appleId);
    const bobLogin = await loginAs(app, bob.appleId);
    aliceAccess = aliceLogin.accessToken;
    bobAccess = bobLogin.accessToken;
  });

  it("Alice's circle list excludes Bob's circle", async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/v1/circles',
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { circles: Array<{ id: string }> };
    expect(body.circles).toHaveLength(1);
    expect(body.circles[0]!.id).toBe(aliceCircle.id);
  });

  it("Alice cannot GET Bob's circle by id (404)", async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot list Bob's activities (404)", async () => {
    await insertActivityRaw(pool, {
      circleId: bobCircle.id,
      authorId: bob.id,
      dek: bobCircle.dek,
      headline: 'Bob secret note',
      content: 'Confidential information',
    });
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}/activities`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot read a single activity in Bob's circle (404)", async () => {
    const activityId = await insertActivityRaw(pool, {
      circleId: bobCircle.id,
      authorId: bob.id,
      dek: bobCircle.dek,
      content: 'Bob private',
    });
    const res = await app.inject({
      method: 'GET',
      url: `/v1/activities/${activityId}`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot create an activity in Bob's circle (404)", async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${bobCircle.id}/activities`,
      headers: bearer(aliceAccess),
      payload: { type: 'text_note', content: 'evil intrusion' },
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot list Bob's medications (404)", async () => {
    await insertMedicationRaw(pool, {
      circleId: bobCircle.id,
      dek: bobCircle.dek,
      name: 'Carbidopa-Levodopa',
      dosage: '25-100 mg',
    });
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}/medications`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot mark a dose for Bob's medication (404)", async () => {
    const medId = await insertMedicationRaw(pool, {
      circleId: bobCircle.id,
      dek: bobCircle.dek,
      name: 'Lisinopril',
      dosage: '10 mg',
    });
    const res = await app.inject({
      method: 'POST',
      url: `/v1/medications/${medId}/doses/mark`,
      headers: bearer(aliceAccess),
      payload: {
        scheduledAt: new Date().toISOString(),
        status: 'taken',
      },
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot list members of Bob's circle (404)", async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}/members`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot list Bob's appointments (404)", async () => {
    await pool.query(
      `INSERT INTO appointments (circle_id, title_enc, starts_at, duration_minutes, created_by)
       VALUES ($1, $2, NOW() + INTERVAL '1 day', 30, $3)`,
      [bobCircle.id, encryptColumn('Cardiology', bobCircle.dek), bob.id],
    );
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}/appointments`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot list Bob's shifts (404)", async () => {
    await pool.query(
      `INSERT INTO care_shifts (circle_id, aide_user_id, starts_at, ends_at)
       VALUES ($1, $2, NOW(), NOW() + INTERVAL '1 hour')`,
      [bobCircle.id, bob.id],
    );
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}/shifts`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot list Bob's documents (404)", async () => {
    await pool.query(
      `INSERT INTO documents (
          circle_id, title_enc, document_type, object_key, mime_type, size_bytes,
          encryption_nonce, encryption_tag, uploaded_by
       ) VALUES ($1, $2, 'insurance_card', 'k/bob.pdf', 'application/pdf', 1234,
                 $3, $4, $5)`,
      [
        bobCircle.id,
        encryptColumn('Bob Insurance', bobCircle.dek),
        Buffer.alloc(12),
        Buffer.alloc(16),
        bob.id,
      ],
    );
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}/documents`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot list Bob's emergency contacts (404)", async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}/emergency-contacts`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot trigger SOS in Bob's circle (404)", async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${bobCircle.id}/sos`,
      headers: bearer(aliceAccess),
      payload: {},
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot read Bob's care recipient (404)", async () => {
    await pool.query(
      `INSERT INTO care_recipients (circle_id, first_name_enc)
       VALUES ($1, $2)`,
      [bobCircle.id, encryptColumn('Martin', bobCircle.dek)],
    );
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}/recipient`,
      headers: bearer(aliceAccess),
    });
    expect(res.statusCode).toBe(404);
  });

  it("Alice cannot create invitations for Bob's circle (404 — not even member)", async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${bobCircle.id}/invitations`,
      headers: bearer(aliceAccess),
      payload: { role: 'family_member' },
    });
    expect(res.statusCode).toBe(404);
  });

  it("View-only Alice in Bob's circle cannot create invitations (403)", async () => {
    // Move Alice into Bob's circle as view_only
    await addMember(pool, {
      circleId: bobCircle.id,
      userId: alice.id,
      role: 'view_only',
      displayName: 'Auntie',
    });
    const res = await app.inject({
      method: 'POST',
      url: `/v1/circles/${bobCircle.id}/invitations`,
      headers: bearer(aliceAccess),
      payload: { role: 'family_member' },
    });
    expect(res.statusCode).toBe(403);
  });

  it("Audit log: Alice's actor id never wrote audit rows for Bob's circle", async () => {
    // Attempt several cross-tenant writes that the API should reject.
    await app.inject({
      method: 'POST',
      url: `/v1/circles/${bobCircle.id}/activities`,
      headers: bearer(aliceAccess),
      payload: { type: 'text_note', content: 'evil intrusion' },
    });
    await app.inject({
      method: 'POST',
      url: `/v1/circles/${bobCircle.id}/invitations`,
      headers: bearer(aliceAccess),
      payload: { role: 'family_member' },
    });
    // No audit_log rows where Alice is the actor and the target row sits in Bob's circle.
    const result = await pool.query<{ n: string }>(
      `SELECT COUNT(*)::TEXT AS n FROM audit_log
        WHERE actor_id = $1 AND circle_id = $2`,
      [alice.id, bobCircle.id],
    );
    expect(Number(result.rows[0]!.n)).toBe(0);
  });

  it("Service role still bypasses RLS (sanity check for internal jobs)", async () => {
    const result = await pool.query<{ id: string }>(
      `SELECT id FROM circles WHERE id = $1`,
      [bobCircle.id],
    );
    expect(result.rows).toHaveLength(1);
  });

  it("Bob can still see his own circle (regression — RLS is not blocking owner)", async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/v1/circles/${bobCircle.id}`,
      headers: bearer(bobAccess),
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { id: string };
    expect(body.id).toBe(bobCircle.id);
  });
});
