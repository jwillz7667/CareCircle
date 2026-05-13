export type ParsedCursor = { occurredAt: string; id: string } | null;

export function parseCursor(raw: string | undefined): ParsedCursor {
  if (!raw) {
    return null;
  }
  try {
    const decoded = Buffer.from(raw, 'base64url').toString('utf8');
    const obj = JSON.parse(decoded) as ParsedCursor;
    if (!obj || typeof obj.occurredAt !== 'string' || typeof obj.id !== 'string') {
      return null;
    }
    return obj;
  } catch {
    return null;
  }
}

export function encodeCursor(occurredAt: Date | string, id: string): string {
  const stamp = occurredAt instanceof Date ? occurredAt.toISOString() : occurredAt;
  return Buffer.from(JSON.stringify({ occurredAt: stamp, id }), 'utf8').toString('base64url');
}
