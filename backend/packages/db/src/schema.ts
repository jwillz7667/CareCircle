import {
  bigint,
  bigserial,
  boolean,
  customType,
  date,
  index,
  integer,
  jsonb,
  numeric,
  pgEnum,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

const bytea = customType<{ data: Buffer; default: false }>({
  dataType() {
    return 'bytea';
  },
});

const inet = customType<{ data: string; default: false }>({
  dataType() {
    return 'inet';
  },
});

export const subscriptionTier = pgEnum('subscription_tier', ['free', 'standard', 'premium']);
export const subscriptionStatus = pgEnum('subscription_status', [
  'trialing',
  'active',
  'past_due',
  'canceled',
  'expired',
]);
export const memberRole = pgEnum('member_role', [
  'owner',
  'family_member',
  'paid_aide',
  'paid_family',
  'care_recipient',
  'view_only',
]);
export const memberStatusEnum = pgEnum('member_status', ['invited', 'active', 'paused', 'removed']);
export const activityType = pgEnum('activity_type', [
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
export const medStatusEnum = pgEnum('med_status', ['active', 'as_needed', 'discontinued']);
export const doseStatusEnum = pgEnum('dose_status', ['scheduled', 'taken', 'skipped', 'missed', 'late']);
export const documentTypeEnum = pgEnum('document_type', [
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

const id = () => uuid('id').primaryKey().defaultRandom();
const createdAt = () => timestamp('created_at', { withTimezone: true }).notNull().defaultNow();
const updatedAt = () => timestamp('updated_at', { withTimezone: true }).notNull().defaultNow();
const deletedAt = () => timestamp('deleted_at', { withTimezone: true });

export const auditLog = pgTable(
  'audit_log',
  {
    id: bigserial('id', { mode: 'bigint' }).primaryKey(),
    occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull().defaultNow(),
    actorId: uuid('actor_id'),
    circleId: uuid('circle_id'),
    action: text('action').notNull(),
    tableName: text('table_name').notNull(),
    rowId: uuid('row_id'),
    diff: jsonb('diff'),
    ipAddress: inet('ip_address'),
    userAgent: text('user_agent'),
  },
  (t) => ({
    circleTimeIdx: index('audit_log_circle_time_idx').on(t.circleId, t.occurredAt),
    actorTimeIdx: index('audit_log_actor_time_idx').on(t.actorId, t.occurredAt),
  }),
);

export const users = pgTable(
  'users',
  {
    id: id(),
    appleUserId: text('apple_user_id').unique(),
    googleUserId: text('google_user_id').unique(),
    passwordHash: text('password_hash'),
    passwordUpdatedAt: timestamp('password_updated_at', { withTimezone: true }),
    email: text('email').unique(),
    isPrivateEmail: boolean('is_private_email').notNull().default(false),
    displayName: text('display_name'),
    photoObjectKey: text('photo_object_key'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    appleIdIdx: index('users_apple_id_idx').on(t.appleUserId),
  }),
);

export const devices = pgTable(
  'devices',
  {
    id: id(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    apnsToken: text('apns_token').notNull(),
    deviceName: text('device_name'),
    osVersion: text('os_version'),
    appVersion: text('app_version'),
    locale: text('locale'),
    timezone: text('timezone'),
    lastActiveAt: timestamp('last_active_at', { withTimezone: true }).notNull().defaultNow(),
    createdAt: createdAt(),
  },
  (t) => ({
    userIdx: index('devices_user_idx').on(t.userId),
    userTokenUq: uniqueIndex('devices_user_token_uq').on(t.userId, t.apnsToken),
  }),
);

export const circles = pgTable(
  'circles',
  {
    id: id(),
    name: text('name').notNull(),
    ownerUserId: uuid('owner_user_id')
      .notNull()
      .references(() => users.id),
    careRecipientId: uuid('care_recipient_id'),
    subscriptionTier: subscriptionTier('subscription_tier').notNull().default('free'),
    subscriptionStatus: subscriptionStatus('subscription_status').notNull().default('active'),
    subscriptionRenewsAt: timestamp('subscription_renews_at', { withTimezone: true }),
    subscriptionProductId: text('subscription_product_id'),
    subscriptionOriginalTransactionId: text('subscription_original_transaction_id').unique(),
    subscriptionGraceUntil: timestamp('subscription_grace_until', { withTimezone: true }),
    subscriptionEnvironment: text('subscription_environment'),
    subscriptionEventAt: timestamp('subscription_event_at', { withTimezone: true }),
    trialUsed: boolean('trial_used').notNull().default(false),
    settings: jsonb('settings').notNull().default(sql`'{}'::jsonb`),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    ownerIdx: index('circles_owner_idx').on(t.ownerUserId),
  }),
);

export const circleKeys = pgTable('circle_keys', {
  circleId: uuid('circle_id')
    .primaryKey()
    .references(() => circles.id, { onDelete: 'cascade' }),
  encryptedDek: bytea('encrypted_dek').notNull(),
  keyVersion: integer('key_version').notNull().default(1),
  createdAt: createdAt(),
  rotatedAt: timestamp('rotated_at', { withTimezone: true }),
});

// Append-only idempotency ledger for App Store Server Notifications V2.
// The webhook dedupes on `notificationUuid`; out-of-order deliveries are
// ledgered but blocked from regressing newer state. See migration 0016.
export const storekitNotifications = pgTable(
  'storekit_notifications',
  {
    notificationUuid: text('notification_uuid').primaryKey(),
    notificationType: text('notification_type').notNull(),
    subtype: text('subtype'),
    circleId: uuid('circle_id').references(() => circles.id, { onDelete: 'set null' }),
    originalTransactionId: text('original_transaction_id'),
    environment: text('environment'),
    signedDate: timestamp('signed_date', { withTimezone: true }),
    applied: boolean('applied').notNull().default(false),
    appliedStatus: subscriptionStatus('applied_status'),
    receivedAt: timestamp('received_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    circleIdx: index('storekit_notifications_circle_idx').on(t.circleId, t.signedDate),
  }),
);

export const careRecipients = pgTable(
  'care_recipients',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    firstNameEnc: bytea('first_name_enc').notNull(),
    lastNameEnc: bytea('last_name_enc'),
    dateOfBirthEnc: bytea('date_of_birth_enc'),
    photoObjectKey: text('photo_object_key'),
    hasUserAccount: boolean('has_user_account').notNull().default(false),
    userId: uuid('user_id').references(() => users.id),
    primaryConditionsEnc: bytea('primary_conditions_enc'),
    pronouns: text('pronouns'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    circleIdx: index('care_recipients_circle_idx').on(t.circleId),
  }),
);

export const circleMembers = pgTable(
  'circle_members',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    role: memberRole('role').notNull(),
    status: memberStatusEnum('status').notNull().default('active'),
    displayName: text('display_name').notNull(),
    permissions: jsonb('permissions').notNull().default(sql`'{}'::jsonb`),
    notificationPrefs: jsonb('notification_prefs')
      .notNull()
      .default(sql`'{"push": true, "digest": "daily"}'::jsonb`),
    invitedBy: uuid('invited_by').references(() => users.id),
    invitedAt: timestamp('invited_at', { withTimezone: true }).notNull().defaultNow(),
    joinedAt: timestamp('joined_at', { withTimezone: true }),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    userIdx: index('circle_members_user_idx').on(t.userId),
    circleIdx: index('circle_members_circle_idx').on(t.circleId),
    circleUserUq: uniqueIndex('circle_members_circle_user_uq').on(t.circleId, t.userId),
  }),
);

export const circleInvitations = pgTable(
  'circle_invitations',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    invitedBy: uuid('invited_by')
      .notNull()
      .references(() => users.id),
    role: memberRole('role').notNull(),
    code: text('code').notNull().unique(),
    inviteLinkId: uuid('invite_link_id').notNull().defaultRandom(),
    email: text('email'),
    phone: text('phone'),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    acceptedAt: timestamp('accepted_at', { withTimezone: true }),
    acceptedBy: uuid('accepted_by').references(() => users.id),
    createdAt: createdAt(),
  },
  (t) => ({
    circleIdx: index('circle_invitations_circle_idx').on(t.circleId),
    linkIdx: index('circle_invitations_link_idx').on(t.inviteLinkId),
  }),
);

export const activities = pgTable(
  'activities',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    authorUserId: uuid('author_user_id')
      .notNull()
      .references(() => users.id),
    activityType: activityType('activity_type').notNull(),
    headline: text('headline'),
    contentEnc: bytea('content_enc'),
    voiceObjectKey: text('voice_object_key'),
    photoObjectKeys: text('photo_object_keys').array(),
    entitiesEnc: bytea('entities_enc'),
    relatedMedId: uuid('related_med_id'),
    relatedAppointmentId: uuid('related_appointment_id'),
    relatedShiftId: uuid('related_shift_id'),
    occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull().defaultNow(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
    version: bigint('version', { mode: 'bigint' }).notNull().default(1n),
    clientOpId: uuid('client_op_id'),
  },
  (t) => ({
    circleTimeIdx: index('activities_circle_time_idx').on(t.circleId, t.occurredAt),
    authorIdx: index('activities_author_idx').on(t.authorUserId),
    medIdx: index('activities_med_idx').on(t.relatedMedId),
  }),
);

export const activityReactions = pgTable(
  'activity_reactions',
  {
    id: id(),
    activityId: uuid('activity_id')
      .notNull()
      .references(() => activities.id, { onDelete: 'cascade' }),
    circleId: uuid('circle_id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    emoji: text('emoji').notNull(),
    createdAt: createdAt(),
  },
  (t) => ({
    activityIdx: index('reactions_activity_idx').on(t.activityId),
    unique: uniqueIndex('reactions_activity_user_emoji_uq').on(t.activityId, t.userId, t.emoji),
  }),
);

export const activityComments = pgTable(
  'activity_comments',
  {
    id: id(),
    activityId: uuid('activity_id')
      .notNull()
      .references(() => activities.id, { onDelete: 'cascade' }),
    circleId: uuid('circle_id').notNull(),
    authorUserId: uuid('author_user_id')
      .notNull()
      .references(() => users.id),
    contentEnc: bytea('content_enc').notNull(),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    activityIdx: index('comments_activity_idx').on(t.activityId, t.createdAt),
  }),
);

export const medications = pgTable(
  'medications',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    nameEnc: bytea('name_enc').notNull(),
    genericNameEnc: bytea('generic_name_enc'),
    dosageEnc: bytea('dosage_enc').notNull(),
    form: text('form'),
    rxcui: text('rxcui'),
    color: text('color'),
    status: medStatusEnum('status').notNull().default('active'),
    schedule: jsonb('schedule').notNull().default(sql`'{}'::jsonb`),
    prescribingProviderEnc: bytea('prescribing_provider_enc'),
    pharmacyEnc: bytea('pharmacy_enc'),
    notesEnc: bytea('notes_enc'),
    startDate: date('start_date'),
    endDate: date('end_date'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    circleIdx: index('medications_circle_idx').on(t.circleId),
  }),
);

export const doseEvents = pgTable(
  'dose_events',
  {
    id: id(),
    medicationId: uuid('medication_id')
      .notNull()
      .references(() => medications.id, { onDelete: 'cascade' }),
    circleId: uuid('circle_id').notNull(),
    scheduledAt: timestamp('scheduled_at', { withTimezone: true }).notNull(),
    takenAt: timestamp('taken_at', { withTimezone: true }),
    markedBy: uuid('marked_by').references(() => users.id),
    status: doseStatusEnum('status').notNull().default('scheduled'),
    notesEnc: bytea('notes_enc'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => ({
    medIdx: index('dose_events_med_time_idx').on(t.medicationId, t.scheduledAt),
    circleIdx: index('dose_events_circle_time_idx').on(t.circleId, t.scheduledAt),
  }),
);

export const appointments = pgTable(
  'appointments',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    titleEnc: bytea('title_enc').notNull(),
    providerEnc: bytea('provider_enc'),
    locationEnc: bytea('location_enc'),
    startsAt: timestamp('starts_at', { withTimezone: true }).notNull(),
    durationMinutes: integer('duration_minutes').notNull().default(60),
    transportResponsible: uuid('transport_responsible').references(() => users.id),
    prepNotesEnc: bytea('prep_notes_enc'),
    visitSummaryEnc: bytea('visit_summary_enc'),
    reminderMinutesBefore: integer('reminder_minutes_before').array().notNull().default([1440, 60]),
    createdBy: uuid('created_by')
      .notNull()
      .references(() => users.id),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    circleTimeIdx: index('appointments_circle_time_idx').on(t.circleId, t.startsAt),
  }),
);

export const appointmentAttendees = pgTable(
  'appointment_attendees',
  {
    appointmentId: uuid('appointment_id')
      .notNull()
      .references(() => appointments.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    circleId: uuid('circle_id').notNull(),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.appointmentId, t.userId] }),
  }),
);

export const careShifts = pgTable(
  'care_shifts',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    aideUserId: uuid('aide_user_id')
      .notNull()
      .references(() => users.id),
    startsAt: timestamp('starts_at', { withTimezone: true }).notNull(),
    endsAt: timestamp('ends_at', { withTimezone: true }).notNull(),
    actualStart: timestamp('actual_start', { withTimezone: true }),
    actualEnd: timestamp('actual_end', { withTimezone: true }),
    services: text('services').array().notNull().default([]),
    notesEnc: bytea('notes_enc'),
    milesDriven: numeric('miles_driven', { precision: 6, scale: 2 }),
    geofenceAutoDetected: boolean('geofence_auto_detected').notNull().default(false),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    circleTimeIdx: index('care_shifts_circle_time_idx').on(t.circleId, t.startsAt),
    aideIdx: index('care_shifts_aide_idx').on(t.aideUserId),
  }),
);

export const documents = pgTable(
  'documents',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    titleEnc: bytea('title_enc').notNull(),
    documentType: documentTypeEnum('document_type').notNull(),
    objectKey: text('object_key').notNull(),
    mimeType: text('mime_type').notNull(),
    sizeBytes: bigint('size_bytes', { mode: 'bigint' }).notNull(),
    encryptionNonce: bytea('encryption_nonce').notNull(),
    encryptionTag: bytea('encryption_tag').notNull(),
    issuedAt: date('issued_at'),
    expiresAt: date('expires_at'),
    uploadedBy: uuid('uploaded_by')
      .notNull()
      .references(() => users.id),
    visibility: memberRole('visibility').array().notNull().default(['owner', 'family_member', 'paid_family', 'care_recipient']),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    circleIdx: index('documents_circle_idx').on(t.circleId),
  }),
);

export const emergencyContacts = pgTable(
  'emergency_contacts',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    nameEnc: bytea('name_enc').notNull(),
    relationship: text('relationship'),
    phoneEnc: bytea('phone_enc').notNull(),
    isPrimary: boolean('is_primary').notNull().default(false),
    isMedical: boolean('is_medical').notNull().default(false),
    sortOrder: integer('sort_order').notNull().default(100),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    circleIdx: index('emergency_contacts_circle_idx').on(t.circleId, t.sortOrder),
  }),
);

export const sosEvents = pgTable(
  'sos_events',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    triggeredBy: uuid('triggered_by')
      .notNull()
      .references(() => users.id),
    triggeredAt: timestamp('triggered_at', { withTimezone: true }).notNull().defaultNow(),
    canceledAt: timestamp('canceled_at', { withTimezone: true }),
    canceledBy: uuid('canceled_by').references(() => users.id),
    locationLat: numeric('location_lat', { precision: 9, scale: 6 }),
    locationLng: numeric('location_lng', { precision: 9, scale: 6 }),
    locationAccuracyM: numeric('location_accuracy_m', { precision: 6, scale: 1 }),
    notifiedUserIds: uuid('notified_user_ids').array().notNull().default(sql`ARRAY[]::UUID[]`),
    primaryContactCalled: boolean('primary_contact_called').notNull().default(false),
    resolutionNotesEnc: bytea('resolution_notes_enc'),
  },
  (t) => ({
    circleTimeIdx: index('sos_circle_time_idx').on(t.circleId, t.triggeredAt),
  }),
);

export const careMinuteEntries = pgTable(
  'care_minute_entries',
  {
    id: id(),
    circleId: uuid('circle_id')
      .notNull()
      .references(() => circles.id, { onDelete: 'cascade' }),
    caregiverUserId: uuid('caregiver_user_id')
      .notNull()
      .references(() => users.id),
    shiftId: uuid('shift_id').references(() => careShifts.id),
    serviceCode: text('service_code').notNull(),
    serviceDescription: text('service_description').notNull(),
    startedAt: timestamp('started_at', { withTimezone: true }).notNull(),
    endedAt: timestamp('ended_at', { withTimezone: true }).notNull(),
    durationMinutes: integer('duration_minutes').notNull(),
    notesEnc: bytea('notes_enc'),
    fiscalIntermediary: text('fiscal_intermediary'),
    exportedAt: timestamp('exported_at', { withTimezone: true }),
    exportPdfKey: text('export_pdf_key'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
    deletedAt: deletedAt(),
  },
  (t) => ({
    circleTimeIdx: index('care_min_circle_time_idx').on(t.circleId, t.startedAt),
    caregiverIdx: index('care_min_caregiver_idx').on(t.caregiverUserId, t.startedAt),
  }),
);

export const pendingOperations = pgTable(
  'pending_operations',
  {
    id: id(),
    clientOpId: uuid('client_op_id').notNull(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id),
    circleId: uuid('circle_id'),
    operationType: text('operation_type').notNull(),
    payload: jsonb('payload').notNull(),
    processedAt: timestamp('processed_at', { withTimezone: true }),
    result: jsonb('result'),
    error: text('error'),
    receivedAt: timestamp('received_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    userIdx: index('pending_ops_user_idx').on(t.userId, t.receivedAt),
    userOpUq: uniqueIndex('pending_ops_user_op_uq').on(t.userId, t.clientOpId),
  }),
);

export const refreshTokens = pgTable(
  'refresh_tokens',
  {
    id: id(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    tokenHash: text('token_hash').notNull().unique(),
    issuedAt: timestamp('issued_at', { withTimezone: true }).notNull().defaultNow(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    lastUsedAt: timestamp('last_used_at', { withTimezone: true }),
    rotatedFrom: uuid('rotated_from'),
    revokedAt: timestamp('revoked_at', { withTimezone: true }),
    userAgent: text('user_agent'),
    ipAddress: inet('ip_address'),
  },
  (t) => ({
    userIdx: index('refresh_tokens_user_idx').on(t.userId, t.revokedAt),
    hashIdx: index('refresh_tokens_hash_idx').on(t.tokenHash),
  }),
);
