import { encryptColumn, decryptColumn } from '@carecircle/shared';
import type { CircleKeyService } from '../services/circleKeys.js';

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

export async function cipherFor(
  keys: CircleKeyService,
  circleId: string,
): Promise<FieldCipher> {
  const dek = await keys.getOrCreate(circleId);
  return new FieldCipher(circleId, dek);
}
