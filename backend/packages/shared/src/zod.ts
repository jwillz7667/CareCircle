import { z } from 'zod';

export const uuidSchema = z.string().uuid();
export const emailSchema = z.string().email().max(320);
export const isoTimestampSchema = z.string().datetime({ offset: true });

export const memberRoleSchema = z.enum([
  'owner',
  'family_member',
  'paid_aide',
  'paid_family',
  'care_recipient',
  'view_only',
]);
export type MemberRoleT = z.infer<typeof memberRoleSchema>;

export const activityTypeSchema = z.enum([
  'voice_note',
  'text_note',
  'photo',
  'med_taken',
  'med_skipped',
  'med_missed',
  'vital_logged',
  'appointment_logged',
  'shift_started',
  'shift_ended',
  'document_added',
  'sos_triggered',
  'system',
]);

export const doseStatusSchema = z.enum(['scheduled', 'taken', 'skipped', 'missed', 'late']);
export const medStatusSchema = z.enum(['active', 'as_needed', 'discontinued']);
export const documentTypeSchema = z.enum([
  'insurance_card',
  'advance_directive',
  'dnr',
  'med_list',
  'visit_summary',
  'eob',
  'lab_result',
  'identification',
  'other',
]);

export const paginationSchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

export const createCircleSchema = z.object({
  name: z.string().min(1).max(120),
});

export const updateCircleSchema = z.object({
  name: z.string().min(1).max(120).optional(),
  settings: z.record(z.unknown()).optional(),
});

export const careRecipientSchema = z.object({
  firstName: z.string().min(1).max(80),
  lastName: z.string().max(120).optional(),
  dateOfBirth: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  pronouns: z.string().max(40).optional(),
  primaryConditions: z.array(z.string().min(1).max(120)).max(20).optional(),
});

export const createInvitationSchema = z.object({
  role: memberRoleSchema,
  email: emailSchema.optional(),
  phone: z.string().max(40).optional(),
  expiresInDays: z.number().int().min(1).max(30).default(7),
});

export const createActivitySchema = z.object({
  type: activityTypeSchema,
  headline: z.string().max(280).optional(),
  content: z.string().max(10_000).optional(),
  voiceObjectKey: z.string().max(500).optional(),
  photoObjectKeys: z.array(z.string().max(500)).max(10).optional(),
  entities: z.array(z.string().max(200)).max(50).optional(),
  relatedMedId: uuidSchema.optional(),
  relatedAppointmentId: uuidSchema.optional(),
  relatedShiftId: uuidSchema.optional(),
  occurredAt: isoTimestampSchema.optional(),
  clientOpId: uuidSchema.optional(),
});

export const reactionSchema = z.object({
  emoji: z.string().min(1).max(16),
});

export const commentSchema = z.object({
  content: z.string().min(1).max(2_000),
});

export const medicationScheduleSchema = z.object({
  times: z.array(z.string().regex(/^\d{2}:\d{2}$/)).max(8).default([]),
  intervalHours: z.number().int().min(1).max(72).optional(),
  daysOfWeek: z.array(z.number().int().min(0).max(6)).optional(),
});

export const createMedicationSchema = z.object({
  name: z.string().min(1).max(200),
  genericName: z.string().max(200).optional(),
  dosage: z.string().min(1).max(120),
  form: z.string().max(60).optional(),
  rxcui: z.string().max(40).optional(),
  color: z.string().max(40).optional(),
  status: medStatusSchema.default('active'),
  schedule: medicationScheduleSchema.optional(),
  prescribingProvider: z.string().max(200).optional(),
  pharmacy: z.string().max(200).optional(),
  notes: z.string().max(2_000).optional(),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export const markDoseSchema = z.object({
  scheduledAt: isoTimestampSchema,
  status: doseStatusSchema,
  notes: z.string().max(500).optional(),
});

export const createAppointmentSchema = z.object({
  title: z.string().min(1).max(200),
  provider: z.string().max(200).optional(),
  location: z.string().max(200).optional(),
  startsAt: isoTimestampSchema,
  durationMinutes: z.number().int().min(5).max(24 * 60).default(60),
  transportResponsible: uuidSchema.optional(),
  prepNotes: z.string().max(2_000).optional(),
  reminderMinutesBefore: z.array(z.number().int().min(0).max(60 * 24 * 14)).max(6).optional(),
  attendees: z.array(uuidSchema).max(20).optional(),
});

export const createShiftSchema = z.object({
  aideUserId: uuidSchema,
  startsAt: isoTimestampSchema,
  endsAt: isoTimestampSchema,
  services: z.array(z.string().max(20)).max(20).optional(),
  notes: z.string().max(2_000).optional(),
});

export const createDocumentSchema = z.object({
  title: z.string().min(1).max(200),
  documentType: documentTypeSchema,
  objectKey: z.string().min(1).max(500),
  mimeType: z.string().min(1).max(120),
  sizeBytes: z.number().int().min(1).max(50 * 1024 * 1024),
  encryptionNonce: z.string().min(1),
  encryptionTag: z.string().min(1),
  issuedAt: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  expiresAt: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  visibility: z.array(memberRoleSchema).min(1).max(6).optional(),
});

export const uploadUrlSchema = z.object({
  bucket: z.enum(['cc-photos', 'cc-voice', 'cc-documents', 'cc-pdf-exports']),
  contentType: z.string().min(1).max(120),
  sizeBytes: z.number().int().min(1).max(50 * 1024 * 1024),
  filename: z.string().max(200).optional(),
});

export const emergencyContactSchema = z.object({
  name: z.string().min(1).max(120),
  relationship: z.string().max(80).optional(),
  phone: z.string().min(3).max(40),
  isPrimary: z.boolean().default(false),
  isMedical: z.boolean().default(false),
  sortOrder: z.number().int().min(0).max(1000).default(100),
});

export const triggerSosSchema = z.object({
  // Client-generated id of the local SOSEvent. Supplying it makes the trigger
  // idempotent: a retry of the same fire (flaky network, app relaunch) lands on
  // the same row instead of double-inserting and double-paging the Circle.
  // Omitted by older clients, in which case the server mints the id.
  eventId: uuidSchema.optional(),
  locationLat: z.number().min(-90).max(90).optional(),
  locationLng: z.number().min(-180).max(180).optional(),
  locationAccuracyM: z.number().min(0).max(10_000).optional(),
});

export const careMinuteSchema = z.object({
  shiftId: uuidSchema.optional(),
  serviceCode: z.string().min(1).max(20),
  serviceDescription: z.string().min(1).max(300),
  startedAt: isoTimestampSchema,
  endedAt: isoTimestampSchema,
  notes: z.string().max(2_000).optional(),
  fiscalIntermediary: z.string().max(80).optional(),
});

export const exportCareMinutesSchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  fiscalIntermediary: z.string().max(80).optional(),
});

export const appleAuthSchema = z.object({
  identityToken: z.string().min(20).max(8_000),
  nonce: z.string().min(1).max(200).optional(),
  givenName: z.string().max(80).optional(),
  familyName: z.string().max(120).optional(),
});

export const refreshAuthSchema = z.object({
  refreshToken: z.string().min(20).max(500),
});

// Email + password sign-in. Password rules follow NIST 800-63B:
// min 12 chars, no required complexity classes, but we cap length so
// an attacker cannot DoS the Argon2 verifier with a megabyte input.
// Email is lowercased + trimmed at the route boundary before reaching
// the DB so case-only variants collapse to a single account.
export const emailRegisterSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(320),
  password: z.string().min(12).max(128),
  displayName: z.string().trim().min(1).max(80).optional(),
});

export const emailLoginSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(320),
  password: z.string().min(1).max(128),
});

// Google ID token comes in via the iOS GoogleSignIn SDK or
// ASWebAuthenticationSession code-exchange flow. We accept the raw
// JWT — backend verifies against Google's JWKS.
export const googleAuthSchema = z.object({
  idToken: z.string().min(20).max(8_000),
  givenName: z.string().max(80).optional(),
  familyName: z.string().max(120).optional(),
});

export const registerDeviceSchema = z.object({
  apnsToken: z.string().min(40).max(200),
  deviceName: z.string().max(80).optional(),
  osVersion: z.string().max(40).optional(),
  appVersion: z.string().max(40).optional(),
  locale: z.string().max(20).optional(),
  timezone: z.string().max(80).optional(),
});

export const updateMeSchema = z.object({
  displayName: z.string().min(1).max(80).optional(),
  photoObjectKey: z.string().max(500).optional(),
});

export const syncBatchSchema = z.object({
  operations: z
    .array(
      z.object({
        clientOpId: uuidSchema,
        operationType: z.string().min(1).max(80),
        circleId: uuidSchema.optional(),
        payload: z.record(z.unknown()),
      }),
    )
    .min(1)
    .max(100),
});

export const syncStatusSchema = z.object({
  clientOpIds: z.array(uuidSchema).min(1).max(500),
});

// 'pending'  — accepted, projection not yet attempted
// 'applied'  — projected into its domain table
// 'failed'   — permanently rejected (bad payload / constraint); do not retry
// 'unknown'  — backend has no record; the client should resend
export const syncOpStatusSchema = z.enum(['pending', 'applied', 'failed', 'unknown']);
export type SyncOpStatusT = z.infer<typeof syncOpStatusSchema>;

export const acceptInvitationSchema = z.object({
  displayName: z.string().min(1).max(80).optional(),
});

export const extractionConfidenceSchema = z.enum(['low', 'medium', 'high']);
export type ExtractionConfidenceT = z.infer<typeof extractionConfidenceSchema>;

export const extractedEntitySchema = z.object({
  id: uuidSchema,
  name: z.string().min(1).max(200),
  details: z.string().max(500).nullable().optional(),
  confidence: extractionConfidenceSchema,
});
export type ExtractedEntityT = z.infer<typeof extractedEntitySchema>;

export const extractedEntitiesSchema = z.object({
  medications: z.array(extractedEntitySchema).max(50).default([]),
  vitals: z.array(extractedEntitySchema).max(50).default([]),
  appointments: z.array(extractedEntitySchema).max(50).default([]),
  meals: z.array(extractedEntitySchema).max(50).default([]),
  symptoms: z.array(extractedEntitySchema).max(50).default([]),
  generalNotes: z.array(extractedEntitySchema).max(50).default([]),
  summary: z.string().max(280).nullable().optional(),
});
export type ExtractedEntitiesT = z.infer<typeof extractedEntitiesSchema>;

export const inferenceExtractSchema = z.object({
  redactedTranscript: z.string().min(1).max(8_000),
  locale: z.string().min(2).max(20).optional(),
});

export const shiftDigestDoseArtifactSchema = z.object({
  id: uuidSchema,
  medicationName: z.string().min(1).max(200),
  dosage: z.string().max(120).nullable().optional(),
  scheduledAt: isoTimestampSchema,
  takenAt: isoTimestampSchema.nullable().optional(),
  status: doseStatusSchema,
});

export const shiftDigestAppointmentArtifactSchema = z.object({
  id: uuidSchema,
  title: z.string().min(1).max(200),
  startsAt: isoTimestampSchema,
  durationMinutes: z.number().int().min(0).max(24 * 60),
  attended: z.boolean().nullable().optional(),
});

export const shiftDigestVitalArtifactSchema = z.object({
  id: uuidSchema,
  kind: z.string().min(1).max(40),
  value: z.string().min(1).max(120),
  unit: z.string().max(40).nullable().optional(),
  recordedAt: isoTimestampSchema,
});

export const shiftDigestJournalArtifactSchema = z.object({
  id: uuidSchema,
  mood: z.string().max(40).nullable().optional(),
  summary: z.string().min(1).max(280),
  recordedAt: isoTimestampSchema,
});

export const shiftDigestArtifactsSchema = z.object({
  doses: z.array(shiftDigestDoseArtifactSchema).max(200).default([]),
  appointments: z.array(shiftDigestAppointmentArtifactSchema).max(50).default([]),
  vitals: z.array(shiftDigestVitalArtifactSchema).max(100).default([]),
  journal: z.array(shiftDigestJournalArtifactSchema).max(50).default([]),
});
export type ShiftDigestArtifactsT = z.infer<typeof shiftDigestArtifactsSchema>;

export const createShiftDigestSchema = z.object({
  shiftStartAt: isoTimestampSchema,
  shiftEndAt: isoTimestampSchema,
  transcript: z.string().max(20_000).optional(),
  summary: z.string().max(2_000).optional(),
  entities: extractedEntitiesSchema.optional(),
  artifacts: shiftDigestArtifactsSchema.optional(),
  voiceObjectKey: z.string().max(500).optional(),
  audioDurationSeconds: z.number().min(0).max(60 * 60).default(0),
  relatedShiftId: uuidSchema.optional(),
  clientOpId: uuidSchema.optional(),
});
export type CreateShiftDigestT = z.infer<typeof createShiftDigestSchema>;

export const vitalKindSchema = z.enum([
  'heart_rate',
  'blood_pressure_systolic',
  'blood_pressure_diastolic',
  'body_weight',
  'blood_glucose',
  'oxygen_saturation',
  'body_temperature',
  'respiratory_rate',
  'falls',
  'walking_steadiness',
  'sleep_hours',
  'resting_heart_rate',
  'step_count',
]);
export type VitalKindT = z.infer<typeof vitalKindSchema>;

export const vitalSourceSchema = z.enum(['manual', 'healthkit']);
export type VitalSourceT = z.infer<typeof vitalSourceSchema>;

export const createVitalSchema = z
  .object({
    kind: vitalKindSchema,
    recordedAt: isoTimestampSchema,
    valueNumeric: z.number().finite().optional(),
    valueText: z.string().min(1).max(120).optional(),
    unit: z.string().min(1).max(40),
    source: vitalSourceSchema.default('manual'),
    healthkitUUID: z.string().min(1).max(120).optional(),
    notes: z.string().max(2_000).optional(),
    clientOpId: uuidSchema.optional(),
  })
  .refine(
    (input) => input.valueNumeric !== undefined || (input.valueText && input.valueText.length > 0),
    { message: 'Either valueNumeric or valueText must be provided', path: ['valueNumeric'] },
  );
export type CreateVitalT = z.infer<typeof createVitalSchema>;

export const listVitalsQuerySchema = paginationSchema.extend({
  kind: vitalKindSchema.optional(),
  source: vitalSourceSchema.optional(),
});
export type ListVitalsQueryT = z.infer<typeof listVitalsQuerySchema>;

// StoreKit signed transactions come in as the JWS compact string —
// caps are large enough to fit Apple's payloads (a couple KB) but not
// so large that a malicious client can DoS the verifier.
export const subscriptionSyncSchema = z.object({
  circleId: uuidSchema,
  signedTransaction: z.string().min(20).max(20_000),
  signedRenewalInfo: z.string().min(20).max(20_000).optional(),
});
export type SubscriptionSyncT = z.infer<typeof subscriptionSyncSchema>;

export const appStoreNotificationSchema = z.object({
  signedPayload: z.string().min(20).max(40_000),
});
export type AppStoreNotificationT = z.infer<typeof appStoreNotificationSchema>;
