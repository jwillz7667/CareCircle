import type pg from 'pg';
import { withRls } from '@carecircle/db';
import type { Logger } from '@carecircle/shared';
import type { Config } from '../config.js';
import type { PushJobData } from '../queues.js';
import { sendApnsNotification } from '../services/apns.js';

type DeviceRow = {
  id: string;
  user_id: string;
  apns_token: string;
};

export async function runPushJob(
  data: PushJobData,
  ctx: { pool: pg.Pool; config: Config; logger: Logger },
): Promise<{ delivered: number; failed: number; tokens: number }> {
  const { pool, config, logger } = ctx;
  if (data.userIds.length === 0) {
    return { delivered: 0, failed: 0, tokens: 0 };
  }
  const devices = await withRls(pool, { role: 'app_service' }, async (client) => {
    const result = await client.query<DeviceRow>(
      `SELECT id, user_id, apns_token
       FROM devices
       WHERE user_id = ANY($1::uuid[])`,
      [data.userIds],
    );
    return result.rows;
  });
  let delivered = 0;
  let failed = 0;
  for (const device of devices) {
    try {
      await sendApnsNotification(device.apns_token, data, config, logger);
      delivered += 1;
    } catch (err) {
      failed += 1;
      logger.warn(
        { err, deviceId: device.id, userId: device.user_id },
        'apns delivery failed',
      );
    }
  }
  return { delivered, failed, tokens: devices.length };
}
