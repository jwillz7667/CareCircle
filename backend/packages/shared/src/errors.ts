export type ErrorCode =
  | 'unauthorized'
  | 'forbidden'
  | 'not_found'
  | 'conflict'
  | 'validation_failed'
  | 'rate_limited'
  | 'apple_jwt_invalid'
  | 'apple_jwks_unavailable'
  | 'circle_member_cap_reached'
  | 'invitation_expired'
  | 'invitation_already_used'
  | 'idempotent_replay'
  | 'internal_error';

export class HttpError extends Error {
  public readonly status: number;
  public readonly code: ErrorCode;
  public readonly details?: Record<string, unknown>;

  constructor(status: number, code: ErrorCode, message: string, details?: Record<string, unknown>) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
    this.name = 'HttpError';
  }
}

export const unauthorized = (msg = 'Unauthorized') => new HttpError(401, 'unauthorized', msg);
export const forbidden = (msg = 'Forbidden') => new HttpError(403, 'forbidden', msg);
export const notFound = (msg = 'Not found') => new HttpError(404, 'not_found', msg);
export const conflict = (msg: string, details?: Record<string, unknown>) =>
  new HttpError(409, 'conflict', msg, details);
// Business-rule validation (e.g. HCBS code not in code-set, end-before-start).
// Schema-shape validation goes through ZodError → 400 in the error handler.
export const validationFailed = (details: Record<string, unknown>) =>
  new HttpError(422, 'validation_failed', 'Validation failed', details);
export const internal = (msg = 'Internal error') => new HttpError(500, 'internal_error', msg);
