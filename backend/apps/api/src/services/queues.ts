import { Queue, type ConnectionOptions, type DefaultJobOptions } from 'bullmq';
import type { Config } from '../config.js';

// Without retries a transient Redis/APNs/OpenFDA blip drops the job silently;
// without removal policies completed/failed jobs accumulate in Redis forever.
// Failures are kept a week for triage; successes are trimmed aggressively.
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
  account: 'cc.account',
} as const;

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

export type SyncJobData = {
  userId: string;
};

/** Cascading teardown after a user soft-deletes their account. */
export type AccountDeletionJobData = {
  userId: string;
};

export interface QueueClient {
  push: Queue<PushJobData>;
  openFda: Queue<OpenFdaJobData>;
  pdf: Queue<PdfJobData>;
  digest: Queue<DigestJobData>;
  sync: Queue<SyncJobData>;
  account: Queue<AccountDeletionJobData>;
  close(): Promise<void>;
}

export function createQueueClient(config: Config): QueueClient {
  const connection: ConnectionOptions = {
    url: config.REDIS_URL,
    maxRetriesPerRequest: null,
  };
  const defaultJobOptions = DEFAULT_JOB_OPTIONS;
  const push = new Queue<PushJobData>(QUEUE_NAMES.push, { connection, defaultJobOptions });
  const openFda = new Queue<OpenFdaJobData>(QUEUE_NAMES.openFda, { connection, defaultJobOptions });
  const pdf = new Queue<PdfJobData>(QUEUE_NAMES.pdf, { connection, defaultJobOptions });
  const digest = new Queue<DigestJobData>(QUEUE_NAMES.digest, { connection, defaultJobOptions });
  const sync = new Queue<SyncJobData>(QUEUE_NAMES.sync, { connection, defaultJobOptions });
  const account = new Queue<AccountDeletionJobData>(QUEUE_NAMES.account, {
    connection,
    defaultJobOptions,
  });
  return {
    push,
    openFda,
    pdf,
    digest,
    sync,
    account,
    async close() {
      await Promise.all([
        push.close(),
        openFda.close(),
        pdf.close(),
        digest.close(),
        sync.close(),
        account.close(),
      ]);
    },
  };
}
