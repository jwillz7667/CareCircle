import { Queue, type ConnectionOptions, type DefaultJobOptions } from 'bullmq';

// Mirrors the API-side policy: retry transient failures, keep failures a week
// for triage, trim successes so Redis doesn't grow unbounded.
const DEFAULT_JOB_OPTIONS: DefaultJobOptions = {
  attempts: 5,
  backoff: { type: 'exponential', delay: 2_000 },
  removeOnComplete: { age: 3_600, count: 1_000 },
  removeOnFail: { age: 7 * 24 * 3_600 },
};

export const QUEUE_NAMES = {
  push: 'cc.push',
  openFda: 'cc.openfda',
  pdf: 'cc.pdf',
  digest: 'cc.digest',
  sync: 'cc.sync',
} as const;

export type QueueName = (typeof QUEUE_NAMES)[keyof typeof QUEUE_NAMES];

export type PushJobData = {
  userIds: string[];
  circleId: string;
  alert: { title: string; body: string };
  payload?: Record<string, unknown>;
  category?: string;
  threadId?: string;
  critical?: boolean;
};

export type OpenFdaJobData = {
  rxcui?: string;
  ndc?: string;
  brandName?: string;
  enqueuedBy: string;
};

export type PdfJobData = {
  jobType: 'care_minutes_export';
  circleId: string;
  caregiverUserId: string;
  startDate: string;
  endDate: string;
  fiscalIntermediary?: string;
};

export type DigestJobData = {
  circleId: string;
  userId: string;
};

/**
 * Drains the submitting user's unprocessed `pending_operations` rows into
 * their domain tables. Keyed by user so a single in-flight job coalesces a
 * burst of `/v1/sync/batch` calls; the drain itself reselects until empty.
 */
export type SyncJobData = {
  userId: string;
};

export function buildConnection(redisUrl: string): ConnectionOptions {
  return { url: redisUrl, maxRetriesPerRequest: null };
}

export function createQueues(connection: ConnectionOptions): {
  push: Queue<PushJobData>;
  openFda: Queue<OpenFdaJobData>;
  pdf: Queue<PdfJobData>;
  digest: Queue<DigestJobData>;
  sync: Queue<SyncJobData>;
  closeAll: () => Promise<void>;
} {
  const defaultJobOptions = DEFAULT_JOB_OPTIONS;
  const push = new Queue<PushJobData>(QUEUE_NAMES.push, { connection, defaultJobOptions });
  const openFda = new Queue<OpenFdaJobData>(QUEUE_NAMES.openFda, { connection, defaultJobOptions });
  const pdf = new Queue<PdfJobData>(QUEUE_NAMES.pdf, { connection, defaultJobOptions });
  const digest = new Queue<DigestJobData>(QUEUE_NAMES.digest, { connection, defaultJobOptions });
  const sync = new Queue<SyncJobData>(QUEUE_NAMES.sync, { connection, defaultJobOptions });
  return {
    push,
    openFda,
    pdf,
    digest,
    sync,
    async closeAll() {
      await Promise.all([
        push.close(),
        openFda.close(),
        pdf.close(),
        digest.close(),
        sync.close(),
      ]);
    },
  };
}
