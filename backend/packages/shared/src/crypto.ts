import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  scryptSync,
  timingSafeEqual,
} from 'node:crypto';

const ALG = 'aes-256-gcm';

export function deriveKey(masterKey: string, salt: string): Buffer {
  return scryptSync(masterKey, salt, 32);
}

export type Sealed = {
  ciphertext: Buffer;
  nonce: Buffer;
  authTag: Buffer;
};

export function sealWithKey(plaintext: Buffer | string, key: Buffer): Sealed {
  const nonce = randomBytes(12);
  const cipher = createCipheriv(ALG, key, nonce);
  const data = typeof plaintext === 'string' ? Buffer.from(plaintext, 'utf8') : plaintext;
  const ciphertext = Buffer.concat([cipher.update(data), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return { ciphertext, nonce, authTag };
}

export function openWithKey(sealed: Sealed, key: Buffer): Buffer {
  const decipher = createDecipheriv(ALG, key, sealed.nonce);
  decipher.setAuthTag(sealed.authTag);
  return Buffer.concat([decipher.update(sealed.ciphertext), decipher.final()]);
}

// Envelope format for a wrapped DEK:
//   version(1) ‖ salt(16) ‖ nonce(12) ‖ authTag(16) ‖ ciphertext
// The salt is random per wrap, so the KDF derives a distinct wrapping key
// for every circle's DEK — a key recovered for one circle can't unwrap
// another. The salt travels with the ciphertext (like the GCM nonce), so
// the blob is fully self-describing and unwrap needs no side channel. The
// leading version byte lets the KDF parameters evolve without ambiguity.
const DEK_WRAP_VERSION = 1;
const DEK_WRAP_SALT_BYTES = 16;

/**
 * Envelope-encrypt a per-circle DEK with the app master key. Stored as
 * a single bytea so we can read it back with one column.
 */
export function wrapDek(dek: Buffer, masterKey: string): Buffer {
  const salt = randomBytes(DEK_WRAP_SALT_BYTES);
  const wrapKey = scryptSync(masterKey, salt, 32);
  const sealed = sealWithKey(dek, wrapKey);
  return Buffer.concat([
    Buffer.from([DEK_WRAP_VERSION]),
    salt,
    sealed.nonce,
    sealed.authTag,
    sealed.ciphertext,
  ]);
}

export function unwrapDek(wrapped: Buffer, masterKey: string): Buffer {
  const headerLen = 1 + DEK_WRAP_SALT_BYTES + 12 + 16;
  if (wrapped.length < headerLen + 1) {
    throw new Error('Invalid wrapped DEK');
  }
  if (wrapped[0] !== DEK_WRAP_VERSION) {
    throw new Error(`Unsupported wrapped DEK version: ${wrapped[0]}`);
  }
  let offset = 1;
  const salt = wrapped.subarray(offset, (offset += DEK_WRAP_SALT_BYTES));
  const nonce = wrapped.subarray(offset, (offset += 12));
  const authTag = wrapped.subarray(offset, (offset += 16));
  const ciphertext = wrapped.subarray(offset);
  const wrapKey = scryptSync(masterKey, salt, 32);
  return openWithKey({ nonce, authTag, ciphertext }, wrapKey);
}

/**
 * Server-side column encryption: a single bytea blob that contains
 * nonce ‖ authTag ‖ ciphertext. The DEK comes from the per-circle key.
 */
export function encryptColumn(plaintext: string, dek: Buffer): Buffer {
  const { nonce, authTag, ciphertext } = sealWithKey(plaintext, dek);
  return Buffer.concat([nonce, authTag, ciphertext]);
}

export function decryptColumn(blob: Buffer, dek: Buffer): string {
  if (blob.length < 12 + 16) {
    throw new Error('Invalid ciphertext blob');
  }
  const nonce = blob.subarray(0, 12);
  const authTag = blob.subarray(12, 28);
  const ciphertext = blob.subarray(28);
  return openWithKey({ nonce, authTag, ciphertext }, dek).toString('utf8');
}

export function newDek(): Buffer {
  return randomBytes(32);
}

export function hashTokenSHA256(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export function safeEqual(a: string, b: string): boolean {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ba.length !== bb.length) {
    return false;
  }
  return timingSafeEqual(ba, bb);
}
