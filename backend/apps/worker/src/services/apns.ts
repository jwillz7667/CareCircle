import { SignJWT, importPKCS8 } from 'jose';
import { request } from 'undici';
import type { Logger } from '@carecircle/shared';
import type { Config } from '../config.js';
import type { PushJobData } from '../queues.js';

type ApnsTokenCache = {
  token: string;
  expiresAt: number;
};

let cachedToken: ApnsTokenCache | null = null;

async function getApnsAuthToken(config: Config): Promise<string> {
  if (!config.APNS_KEY_ID || !config.APNS_TEAM_ID || !config.APNS_PRIVATE_KEY) {
    throw new Error('APNS credentials not configured');
  }
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) {
    return cachedToken.token;
  }
  const pem = config.APNS_PRIVATE_KEY.replace(/\\n/g, '\n');
  const key = await importPKCS8(pem, 'ES256');
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: config.APNS_KEY_ID })
    .setIssuer(config.APNS_TEAM_ID)
    .setIssuedAt(now)
    .sign(key);
  cachedToken = { token, expiresAt: now + 50 * 60 };
  return token;
}

export async function sendApnsNotification(
  apnsToken: string,
  data: PushJobData,
  config: Config,
  logger: Logger,
): Promise<void> {
  if (config.APNS_MOCK_MODE) {
    logger.info(
      {
        circleId: data.circleId,
        token: apnsToken.slice(0, 8) + '…',
        alert: data.alert,
        critical: !!data.critical,
      },
      'apns mock send',
    );
    return;
  }
  const authToken = await getApnsAuthToken(config);
  const host =
    config.APNS_ENVIRONMENT === 'production'
      ? 'https://api.push.apple.com'
      : 'https://api.sandbox.push.apple.com';
  const body = JSON.stringify({
    aps: {
      alert: data.alert,
      sound: data.critical ? { critical: 1, name: 'default', volume: 1.0 } : 'default',
      'thread-id': data.threadId ?? data.circleId,
      category: data.category,
      'interruption-level': data.critical ? 'critical' : 'time-sensitive',
    },
    ...data.payload,
  });
  const response = await request(`${host}/3/device/${apnsToken}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${authToken}`,
      'apns-topic': config.APNS_BUNDLE_ID,
      'apns-push-type': 'alert',
      'apns-priority': data.critical ? '10' : '5',
    },
    body,
  });
  if (response.statusCode >= 400) {
    const errorText = await response.body.text().catch(() => '');
    throw new Error(`APNs ${response.statusCode}: ${errorText}`);
  }
}
