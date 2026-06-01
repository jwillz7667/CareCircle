/**
 * Subscriptions: client sync applies a verified StoreKit transaction; the
 * App Store webhook is idempotent on notificationUUID and refuses to regress
 * newer state with an out-of-order (stale) delivery.
 */
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { randomUUID } from 'node:crypto';
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
import { loadConfig, type Config } from '../src/config.js';
import {
  signMockStoreKitNotification,
  signMockStoreKitTransaction,
} from '../src/services/storekit.js';

describe('Subscriptions', () => {
  let app: FastifyInstance;
  let pool: pg.Pool;
  let config: Config;
  let owner: SeededUser;
  let circle: SeededCircle;
  let ownerToken: string;

  beforeAll(async () => {
    app = await getTestApp();
    pool = makePool();
    config = loadConfig();
  });
  afterAll(async () => {
    await closeTestApp();
    await pool.end();
  });
  beforeEach(async () => {
    await resetDb(pool);
    owner = await insertUser(pool, { appleId: 'mock|sub-owner' });
    circle = await insertCircle(pool, { ownerId: owner.id, name: 'Sub Circle', tier: 'free' });
    ownerToken = (await loginAs(app, owner.appleId)).accessToken;
  });

  async function syncStandard(originalTransactionId: string): Promise<void> {
    const signedTransaction = await signMockStoreKitTransaction(config, {
      productId: config.STOREKIT_PRODUCT_STANDARD,
      originalTransactionId,
      appAccountToken: circle.id,
      expiresDate: new Date(Date.now() + 30 * 86_400_000),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/v1/subscriptions/sync',
      headers: bearer(ownerToken),
      payload: { circleId: circle.id, signedTransaction },
    });
    expect(res.statusCode).toBe(200);
  }

  it('sync applies a verified transaction and flips the circle to its tier', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/subscriptions/sync',
      headers: bearer(ownerToken),
      payload: {
        circleId: circle.id,
        signedTransaction: await signMockStoreKitTransaction(config, {
          productId: config.STOREKIT_PRODUCT_STANDARD,
          originalTransactionId: randomUUID(),
          appAccountToken: circle.id,
          expiresDate: new Date(Date.now() + 30 * 86_400_000),
        }),
      },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as {
      subscription: { tier: string; status: string };
    };
    expect(body.subscription.tier).toBe('standard');
    expect(body.subscription.status).toBe('active');
  });

  it('webhook dedupes a redelivered notification on notificationUUID', async () => {
    const originalTransactionId = randomUUID();
    await syncStandard(originalTransactionId);

    const at = new Date(Date.now() + 1_000);
    const renewTx = await signMockStoreKitTransaction(config, {
      productId: config.STOREKIT_PRODUCT_STANDARD,
      originalTransactionId,
      expiresDate: new Date(Date.now() + 60 * 86_400_000),
      signedDate: at,
    });
    const notificationUUID = randomUUID();
    const signedPayload = await signMockStoreKitNotification(config, {
      notificationType: 'DID_RENEW',
      notificationUUID,
      signedTransactionInfo: renewTx,
      signedDate: at,
    });

    const first = await app.inject({
      method: 'POST',
      url: '/v1/subscriptions/webhook',
      payload: { signedPayload },
    });
    const second = await app.inject({
      method: 'POST',
      url: '/v1/subscriptions/webhook',
      payload: { signedPayload },
    });
    expect(first.statusCode).toBe(200);
    expect(second.statusCode).toBe(200);

    const ledger = await pool.query<{ n: string; applied: boolean }>(
      `SELECT COUNT(*)::text AS n, BOOL_OR(applied) AS applied
       FROM storekit_notifications WHERE notification_uuid = $1`,
      [notificationUUID],
    );
    expect(ledger.rows[0]!.n).toBe('1');
    expect(ledger.rows[0]!.applied).toBe(true);
  });

  it('out-of-order EXPIRED does not regress newer state', async () => {
    const originalTransactionId = randomUUID();
    await syncStandard(originalTransactionId);

    // A fresh DID_RENEW lands first (signedDate t2).
    const t2 = new Date(Date.now() + 10_000);
    const renewTx = await signMockStoreKitTransaction(config, {
      productId: config.STOREKIT_PRODUCT_STANDARD,
      originalTransactionId,
      expiresDate: new Date(Date.now() + 60 * 86_400_000),
      signedDate: t2,
    });
    await app.inject({
      method: 'POST',
      url: '/v1/subscriptions/webhook',
      payload: {
        signedPayload: await signMockStoreKitNotification(config, {
          notificationType: 'DID_RENEW',
          notificationUUID: randomUUID(),
          signedTransactionInfo: renewTx,
          signedDate: t2,
        }),
      },
    });

    // A stale EXPIRED arrives late (signedDate t0, before t2).
    const t0 = new Date(Date.now() - 10_000);
    const expiredTx = await signMockStoreKitTransaction(config, {
      productId: config.STOREKIT_PRODUCT_STANDARD,
      originalTransactionId,
      expiresDate: new Date(Date.now() - 86_400_000),
      signedDate: t0,
    });
    const staleUUID = randomUUID();
    const stale = await app.inject({
      method: 'POST',
      url: '/v1/subscriptions/webhook',
      payload: {
        signedPayload: await signMockStoreKitNotification(config, {
          notificationType: 'EXPIRED',
          notificationUUID: staleUUID,
          signedTransactionInfo: expiredTx,
          signedDate: t0,
        }),
      },
    });
    expect(stale.statusCode).toBe(200);

    const state = await app.inject({
      method: 'GET',
      url: `/v1/subscriptions/circle/${circle.id}`,
      headers: bearer(ownerToken),
    });
    const body = JSON.parse(state.body) as { subscription: { tier: string; status: string } };
    expect(body.subscription.tier).toBe('standard');
    expect(body.subscription.status).toBe('active');

    const ledger = await pool.query<{ applied: boolean }>(
      `SELECT applied FROM storekit_notifications WHERE notification_uuid = $1`,
      [staleUUID],
    );
    expect(ledger.rows[0]!.applied).toBe(false);
  });
});
