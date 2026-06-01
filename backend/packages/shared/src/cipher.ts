import { encryptColumn, decryptColumn } from './crypto.js';

/**
 * Per-circle column cipher. Wraps a single circle's data-encryption key (DEK)
 * and applies AES-256-GCM to individual column values. Holds no I/O — callers
 * resolve the DEK (API: CircleKeyService, worker: circle-key resolver) and pass
 * it in. Lives in shared so both the API and the worker encrypt identically.
 */
export class FieldCipher {
  constructor(
    private readonly circleId: string,
    private readonly dek: Buffer,
  ) {}

  encrypt(plaintext: string): Buffer {
    return encryptColumn(plaintext, this.dek);
  }

  encryptOptional(plaintext: string | undefined | null): Buffer | null {
    if (plaintext === undefined || plaintext === null) {
      return null;
    }
    return encryptColumn(plaintext, this.dek);
  }

  decrypt(blob: Buffer): string {
    return decryptColumn(blob, this.dek);
  }

  decryptOptional(blob: Buffer | null | undefined): string | null {
    if (!blob) {
      return null;
    }
    return decryptColumn(blob, this.dek);
  }

  encryptJson(value: unknown): Buffer {
    return encryptColumn(JSON.stringify(value), this.dek);
  }

  decryptJson<T = unknown>(blob: Buffer | null | undefined): T | null {
    if (!blob) {
      return null;
    }
    return JSON.parse(decryptColumn(blob, this.dek)) as T;
  }

  get circleIdentifier(): string {
    return this.circleId;
  }
}
