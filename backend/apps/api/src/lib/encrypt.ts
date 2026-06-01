import { FieldCipher } from '@carecircle/shared';
import type { CircleKeyService } from '../services/circleKeys.js';

export { FieldCipher };

export async function cipherFor(keys: CircleKeyService, circleId: string): Promise<FieldCipher> {
  const dek = await keys.getOrCreate(circleId);
  return new FieldCipher(circleId, dek);
}
