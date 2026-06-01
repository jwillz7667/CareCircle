import type pg from 'pg';
import { withRls } from '@carecircle/db';
import type { Logger } from '@carecircle/shared';
import type { Config } from '../config.js';
import type { PushJobData } from '../queues.js';
import { sendApnsNotification } from '../services/apns.js';

type NotificationPrefs = { push?: boolean; digest?: string };

type DeviceRow = {
  id: string;
  user_id: string;
  apns_token: string;
  notification_prefs: NotificationPrefs | null;
};

/**
 * A circle-scoped push respects the recipient's per-circle preferences, with
 * one exception: critical alerts (SOS) are life-safety and bypass the user's
 * mute, mirroring how the iOS critical-alert entitlement pierces Do Not Disturb.
 */
function shouldDeliver(data: PushJobData, prefs: NotificationPrefs | null): boolean {
  if (data.critical) {
    return true;
  }
  if (prefs?.push === false) {
    return false;
  }
  if (data.category === 'cc_digest' && prefs?.digest != null && prefs.digest !== 'daily') {
    return false;
  }
  return true;
}

export async function runPushJob(
  data: PushJobData,
  ctx: { pool: pg.Pool; config: Config; logger: Logger },
): Promise<{ delivered: number; failed: number; tokens: number; suppressed: number }> {
  const { pool, config, logger } = ctx;
  if (data.userIds.length === 0) {
    return { delivered: 0, failed: 0, tokens: 0, suppressed: 0 };
  }
  // Join membership so we read each recipient's per-circle prefs and never
  // push circle content to a former member.
  const devices = await withRls(pool, { role: 'app_service' }, async (client) => {
    const result = await client.query<DeviceRow>(
      `SELECT d.id, d.user_id, d.apns_token, cm.notification_prefs
       FROM devices d
       JOIN circle_members cm
         ON cm.user_id = d.user_id
        AND cm.circle_id = $2
        AND cm.deleted_at IS NULL
       WHERE d.user_id = ANY($1::uuid[])`,
      [data.userIds, data.circleId],
    );
    return result.rows;
  });
  let delivered = 0;
  let failed = 0;
  let suppressed = 0;
  for (const device of devices) {
    if (!shouldDeliver(data, device.notification_prefs)) {
      suppressed += 1;
      continue;
    }
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
  return { delivered, failed, tokens: devices.length, suppressed };
}
