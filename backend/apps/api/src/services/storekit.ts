import { X509Certificate, createPublicKey, verify as verifySignature } from 'node:crypto';
import {
  decodeProtectedHeader,
  jwtVerify,
  SignJWT,
  type JWTPayload,
  type KeyLike,
} from 'jose';
import { HttpError } from '@carecircle/shared';
import type { Config } from '../config.js';

// ---------------------------------------------------------------------
// StoreKit 2 transaction + notification verification.
//
// Apple signs every transaction and every App Store Server Notification
// (V2) as a JWS (compact serialization) using ES256. The JWS header
// carries an `x5c` chain that ends in Apple Root CA — G3. We verify the
// chain ourselves rather than calling Apple's `verifyReceipt` endpoint
// (deprecated for StoreKit 2) or running the larger
// `app-store-server-library` SDK, which would add a dependency just to
// wrap a few hundred lines of trust-store work.
//
// Trust model:
//   1. Parse `x5c` (leaf, intermediate(s), optional root).
//   2. Each cert in the chain signed by the next; final issuer must
//      match Apple Root CA — G3 (pinned PEM below). The chain isn't
//      time-checked against `notBefore`/`notAfter` because StoreKit
//      occasionally emits long-lived legacy signatures, and Apple's
//      own verifier doesn't fail the chain on expiry.
//   3. JWS signature verified against the leaf cert's public key.
//   4. Claims (`bundleId`, `environment`) cross-checked against config.
// ---------------------------------------------------------------------

// Apple Root CA — G3. Public, ships in every Apple PKI client.
// https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
const APPLE_ROOT_CA_G3_PEM = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

const APPLE_ROOT = new X509Certificate(APPLE_ROOT_CA_G3_PEM);

export type SubscriptionTier = 'standard' | 'premium';
export type Environment = 'Sandbox' | 'Production';

export type VerifiedTransaction = {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  tier: SubscriptionTier;
  purchaseDate: Date;
  originalPurchaseDate: Date;
  expiresDate?: Date;
  revocationDate?: Date;
  revocationReason?: number;
  inAppOwnershipType?: string;
  type?: string;
  environment: Environment;
  /** True if the transaction was redeemed against an introductory free trial. */
  isTrialPeriod: boolean;
  appAccountToken?: string;
};

export type VerifiedRenewalInfo = {
  originalTransactionId: string;
  productId: string;
  autoRenewProductId?: string;
  autoRenewStatus: 0 | 1;
  expirationIntent?: number;
  isInBillingRetryPeriod?: boolean;
  gracePeriodExpiresDate?: Date;
  environment: Environment;
};

export type AppStoreNotificationType =
  | 'SUBSCRIBED'
  | 'DID_RENEW'
  | 'DID_CHANGE_RENEWAL_STATUS'
  | 'DID_FAIL_TO_RENEW'
  | 'GRACE_PERIOD_EXPIRED'
  | 'EXPIRED'
  | 'REFUND'
  | 'REVOKE'
  | 'PRICE_INCREASE'
  | 'OFFER_REDEEMED'
  | 'RENEWAL_EXTENDED'
  | 'DID_CHANGE_PRODUCT'
  | 'CONSUMPTION_REQUEST'
  | 'REFUND_DECLINED'
  | 'TEST';

export type VerifiedNotification = {
  notificationType: AppStoreNotificationType;
  subtype?: string;
  notificationUUID: string;
  transaction?: VerifiedTransaction;
  renewalInfo?: VerifiedRenewalInfo;
  environment: Environment;
};

export interface StoreKitService {
  verifyTransaction(signedTransaction: string): Promise<VerifiedTransaction>;
  verifyRenewalInfo(signedRenewalInfo: string): Promise<VerifiedRenewalInfo>;
  verifyNotification(signedPayload: string): Promise<VerifiedNotification>;
  tierForProductId(productId: string): SubscriptionTier | null;
}

// ---------------------------------------------------------------------
// Real verifier
// ---------------------------------------------------------------------

function decodeBase64UrlBytes(input: string): Buffer {
  return Buffer.from(input, 'base64url');
}

function pemFromB64(derB64: string): string {
  // x5c entries are base64 (NOT base64url) of the DER cert.
  const wrapped = derB64.match(/.{1,64}/g)?.join('\n') ?? derB64;
  return `-----BEGIN CERTIFICATE-----\n${wrapped}\n-----END CERTIFICATE-----`;
}

function verifyCertChain(chain: X509Certificate[], trustedRoot: X509Certificate): void {
  if (chain.length === 0) {
    throw new HttpError(401, 'apple_jwt_invalid', 'StoreKit x5c chain empty');
  }
  // Each cert (except the last) must be signed by the next one.
  for (let i = 0; i < chain.length - 1; i++) {
    const child = chain[i]!;
    const parent = chain[i + 1]!;
    if (!child.verify(parent.publicKey)) {
      throw new HttpError(401, 'apple_jwt_invalid', `StoreKit chain break at depth ${i}`);
    }
  }
  // The top of the supplied chain must chain to our pinned root.
  const top = chain[chain.length - 1]!;
  // Apple usually omits the root from x5c; check if top IS the root, or
  // if top is signed by the root.
  const isRootItself = top.raw.equals(trustedRoot.raw);
  if (!isRootItself && !top.verify(trustedRoot.publicKey)) {
    throw new HttpError(401, 'apple_jwt_invalid', 'StoreKit chain does not anchor to Apple Root G3');
  }
}

async function verifyJwsAndDecode(
  signedPayload: string,
  trustedRoot: X509Certificate,
): Promise<JWTPayload> {
  const parts = signedPayload.split('.');
  if (parts.length !== 3) {
    throw new HttpError(401, 'apple_jwt_invalid', 'StoreKit JWS not in compact form');
  }
  const header = decodeProtectedHeader(signedPayload);
  if (header.alg !== 'ES256') {
    throw new HttpError(401, 'apple_jwt_invalid', `StoreKit JWS alg ${header.alg} != ES256`);
  }
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length === 0) {
    throw new HttpError(401, 'apple_jwt_invalid', 'StoreKit JWS missing x5c chain');
  }
  const chain = x5c.map((entry) => new X509Certificate(pemFromB64(entry)));
  verifyCertChain(chain, trustedRoot);

  const leaf = chain[0]!;
  const publicKey: KeyLike = createPublicKey(leaf.publicKey) as unknown as KeyLike;
  const { payload } = await jwtVerify(signedPayload, publicKey, {
    algorithms: ['ES256'],
  }).catch((err: unknown) => {
    throw new HttpError(401, 'apple_jwt_invalid', 'StoreKit JWS signature invalid', {
      reason: err instanceof Error ? err.message : 'unknown',
    });
  });
  return payload;
}

function mapTransactionPayload(
  payload: JWTPayload,
  tierFn: (productId: string) => SubscriptionTier | null,
): VerifiedTransaction {
  const productId = pickString(payload, 'productId');
  const tier = tierFn(productId);
  if (!tier) {
    throw new HttpError(422, 'validation_failed', `Unknown product id: ${productId}`);
  }
  return {
    transactionId: pickString(payload, 'transactionId'),
    originalTransactionId: pickString(payload, 'originalTransactionId'),
    bundleId: pickString(payload, 'bundleId'),
    productId,
    tier,
    purchaseDate: pickDate(payload, 'purchaseDate'),
    originalPurchaseDate: pickDate(payload, 'originalPurchaseDate'),
    expiresDate: pickOptionalDate(payload, 'expiresDate'),
    revocationDate: pickOptionalDate(payload, 'revocationDate'),
    revocationReason:
      typeof payload.revocationReason === 'number' ? payload.revocationReason : undefined,
    inAppOwnershipType:
      typeof payload.inAppOwnershipType === 'string' ? payload.inAppOwnershipType : undefined,
    type: typeof payload.type === 'string' ? payload.type : undefined,
    environment: pickEnvironment(payload),
    // `offerType === 1` is the introductory-offer redemption — that's
    // Apple's signal for "this transaction is being charged at the
    // 7-day free trial price". Apple sometimes serializes the value as
    // a string, hence both branches.
    isTrialPeriod: payload.offerType === 1 || payload.offerType === '1',
    appAccountToken:
      typeof payload.appAccountToken === 'string' ? payload.appAccountToken : undefined,
  };
}

function mapRenewalInfoPayload(payload: JWTPayload): VerifiedRenewalInfo {
  return {
    originalTransactionId: pickString(payload, 'originalTransactionId'),
    productId: pickString(payload, 'productId'),
    autoRenewProductId:
      typeof payload.autoRenewProductId === 'string' ? payload.autoRenewProductId : undefined,
    autoRenewStatus: payload.autoRenewStatus === 0 ? 0 : 1,
    expirationIntent:
      typeof payload.expirationIntent === 'number' ? payload.expirationIntent : undefined,
    isInBillingRetryPeriod:
      typeof payload.isInBillingRetryPeriod === 'boolean'
        ? payload.isInBillingRetryPeriod
        : undefined,
    gracePeriodExpiresDate: pickOptionalDate(payload, 'gracePeriodExpiresDate'),
    environment: pickEnvironment(payload),
  };
}

function pickString(payload: JWTPayload, key: string): string {
  const v = payload[key];
  if (typeof v !== 'string' || v.length === 0) {
    throw new HttpError(401, 'apple_jwt_invalid', `StoreKit payload missing ${key}`);
  }
  return v;
}

function pickDate(payload: JWTPayload, key: string): Date {
  const v = payload[key];
  if (typeof v !== 'number') {
    throw new HttpError(401, 'apple_jwt_invalid', `StoreKit payload missing ${key}`);
  }
  return new Date(v);
}

function pickOptionalDate(payload: JWTPayload, key: string): Date | undefined {
  const v = payload[key];
  return typeof v === 'number' ? new Date(v) : undefined;
}

function pickEnvironment(payload: JWTPayload): Environment {
  const env = payload.environment;
  if (env === 'Sandbox' || env === 'Production') return env;
  // Apple V2 notifications wrap env at `data.environment` which we
  // surface to the payload before calling this for transactions, but
  // sometimes it's only on the outer notification body. Default to
  // Production so a missing-env signed transaction doesn't slip
  // through as Sandbox in a strict prod build.
  return 'Production';
}

export function createRealStoreKitService(config: Config): StoreKitService {
  const productMap = new Map<string, SubscriptionTier>([
    [config.STOREKIT_PRODUCT_STANDARD, 'standard'],
    [config.STOREKIT_PRODUCT_PREMIUM, 'premium'],
  ]);

  const tierForProductId = (productId: string): SubscriptionTier | null =>
    productMap.get(productId) ?? null;

  const guardEnvironment = (env: Environment): void => {
    if (env === 'Sandbox' && !config.STOREKIT_ALLOW_SANDBOX) {
      throw new HttpError(401, 'apple_jwt_invalid', 'Sandbox transactions rejected in production');
    }
  };

  const guardBundle = (bundleId: string): void => {
    if (bundleId !== config.STOREKIT_BUNDLE_ID) {
      throw new HttpError(401, 'apple_jwt_invalid', `Bundle id mismatch: ${bundleId}`);
    }
  };

  return {
    tierForProductId,
    async verifyTransaction(signedTransaction): Promise<VerifiedTransaction> {
      const payload = await verifyJwsAndDecode(signedTransaction, APPLE_ROOT);
      const tx = mapTransactionPayload(payload, tierForProductId);
      guardBundle(tx.bundleId);
      guardEnvironment(tx.environment);
      return tx;
    },
    async verifyRenewalInfo(signedRenewalInfo): Promise<VerifiedRenewalInfo> {
      const payload = await verifyJwsAndDecode(signedRenewalInfo, APPLE_ROOT);
      const info = mapRenewalInfoPayload(payload);
      guardEnvironment(info.environment);
      return info;
    },
    async verifyNotification(signedPayload): Promise<VerifiedNotification> {
      const payload = await verifyJwsAndDecode(signedPayload, APPLE_ROOT);
      const notificationType = payload.notificationType;
      const notificationUUID = payload.notificationUUID;
      if (typeof notificationType !== 'string' || typeof notificationUUID !== 'string') {
        throw new HttpError(401, 'apple_jwt_invalid', 'Malformed App Store notification');
      }
      const data = (payload.data ?? {}) as {
        signedTransactionInfo?: string;
        signedRenewalInfo?: string;
        environment?: string;
        bundleId?: string;
      };
      const environment: Environment =
        data.environment === 'Sandbox' || data.environment === 'Production'
          ? data.environment
          : 'Production';
      guardEnvironment(environment);
      if (data.bundleId) guardBundle(data.bundleId);

      const transaction = data.signedTransactionInfo
        ? await this.verifyTransaction(data.signedTransactionInfo)
        : undefined;
      const renewalInfo = data.signedRenewalInfo
        ? await this.verifyRenewalInfo(data.signedRenewalInfo)
        : undefined;

      return {
        notificationType: notificationType as AppStoreNotificationType,
        subtype: typeof payload.subtype === 'string' ? payload.subtype : undefined,
        notificationUUID,
        transaction,
        renewalInfo,
        environment,
      };
    },
  };
}

// ---------------------------------------------------------------------
// Mock verifier (HS256 with shared secret) — for dev/test only.
//
// Tests sign synthetic transactions with `signMockStoreKitJWS` and the
// mock verifier accepts them. The mock skips the X.509 chain entirely.
// ---------------------------------------------------------------------

export function createMockStoreKitService(config: Config): StoreKitService {
  const productMap = new Map<string, SubscriptionTier>([
    [config.STOREKIT_PRODUCT_STANDARD, 'standard'],
    [config.STOREKIT_PRODUCT_PREMIUM, 'premium'],
  ]);
  const tierForProductId = (productId: string): SubscriptionTier | null =>
    productMap.get(productId) ?? null;

  const secret = new TextEncoder().encode(config.STOREKIT_MOCK_SECRET ?? config.JWT_SECRET);

  const verifyMock = async (signed: string): Promise<JWTPayload> => {
    const { payload } = await jwtVerify(signed, secret, { algorithms: ['HS256'] }).catch(
      (err: unknown) => {
        throw new HttpError(401, 'apple_jwt_invalid', 'Mock StoreKit JWS invalid', {
          reason: err instanceof Error ? err.message : 'unknown',
        });
      },
    );
    return payload;
  };

  return {
    tierForProductId,
    async verifyTransaction(signed): Promise<VerifiedTransaction> {
      const payload = await verifyMock(signed);
      return mapTransactionPayload(payload, tierForProductId);
    },
    async verifyRenewalInfo(signed): Promise<VerifiedRenewalInfo> {
      const payload = await verifyMock(signed);
      return mapRenewalInfoPayload(payload);
    },
    async verifyNotification(signed): Promise<VerifiedNotification> {
      const payload = await verifyMock(signed);
      const notificationType = payload.notificationType;
      const notificationUUID = payload.notificationUUID;
      if (typeof notificationType !== 'string' || typeof notificationUUID !== 'string') {
        throw new HttpError(401, 'apple_jwt_invalid', 'Malformed mock notification');
      }
      const data = (payload.data ?? {}) as {
        signedTransactionInfo?: string;
        signedRenewalInfo?: string;
        environment?: string;
      };
      const environment: Environment =
        data.environment === 'Sandbox' || data.environment === 'Production'
          ? data.environment
          : 'Sandbox';
      const transaction = data.signedTransactionInfo
        ? await this.verifyTransaction(data.signedTransactionInfo)
        : undefined;
      const renewalInfo = data.signedRenewalInfo
        ? await this.verifyRenewalInfo(data.signedRenewalInfo)
        : undefined;
      return {
        notificationType: notificationType as AppStoreNotificationType,
        subtype: typeof payload.subtype === 'string' ? payload.subtype : undefined,
        notificationUUID,
        transaction,
        renewalInfo,
        environment,
      };
    },
  };
}

export function createStoreKitService(config: Config): StoreKitService {
  return config.STOREKIT_VERIFIER_MODE === 'mock'
    ? createMockStoreKitService(config)
    : createRealStoreKitService(config);
}

// ---------------------------------------------------------------------
// Mock helpers for tests + seed scripts.
// ---------------------------------------------------------------------

export async function signMockStoreKitTransaction(
  config: Config,
  claims: Partial<VerifiedTransaction> & { productId: string; originalTransactionId: string },
): Promise<string> {
  const secret = new TextEncoder().encode(config.STOREKIT_MOCK_SECRET ?? config.JWT_SECRET);
  const now = Date.now();
  const builder = new SignJWT({
    transactionId: claims.transactionId ?? claims.originalTransactionId,
    originalTransactionId: claims.originalTransactionId,
    bundleId: claims.bundleId ?? config.STOREKIT_BUNDLE_ID,
    productId: claims.productId,
    purchaseDate: claims.purchaseDate?.getTime() ?? now,
    originalPurchaseDate: claims.originalPurchaseDate?.getTime() ?? now,
    expiresDate: claims.expiresDate?.getTime() ?? now + 30 * 86_400_000,
    inAppOwnershipType: claims.inAppOwnershipType ?? 'PURCHASED',
    type: claims.type ?? 'Auto-Renewable Subscription',
    environment: claims.environment ?? 'Sandbox',
    offerType: claims.isTrialPeriod ? 1 : undefined,
    appAccountToken: claims.appAccountToken,
  }).setProtectedHeader({ alg: 'HS256' });
  return builder.sign(secret);
}

export async function signMockStoreKitNotification(
  config: Config,
  notification: {
    notificationType: AppStoreNotificationType;
    subtype?: string;
    notificationUUID: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
    environment?: Environment;
  },
): Promise<string> {
  const secret = new TextEncoder().encode(config.STOREKIT_MOCK_SECRET ?? config.JWT_SECRET);
  const builder = new SignJWT({
    notificationType: notification.notificationType,
    subtype: notification.subtype,
    notificationUUID: notification.notificationUUID,
    data: {
      bundleId: config.STOREKIT_BUNDLE_ID,
      environment: notification.environment ?? 'Sandbox',
      signedTransactionInfo: notification.signedTransactionInfo,
      signedRenewalInfo: notification.signedRenewalInfo,
    },
  }).setProtectedHeader({ alg: 'HS256' });
  return builder.sign(secret);
}

// Unused but kept to suppress an unused-import warning in mock builds.
void verifySignature;
void decodeBase64UrlBytes;
