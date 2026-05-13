import { Queue, type ConnectionOptions } from 'bullmq';
import type { Config } from '../config.js';

export const QUEUE_NAMES = {
  push: 'cc.push',
  openFda: 'cc.openfda',
  pdf: 'cc.pdf',
  digest: 'cc.digest',
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

export interface QueueClient {
  push: Queue<PushJobData>;
  openFda: Queue<OpenFdaJobData>;
  pdf: Queue<PdfJobData>;
  digest: Queue<DigestJobData>;
  close(): Promise<void>;
}

export function createQueueClient(config: Config): QueueClient {
  const connection: ConnectionOptions = {
    url: config.REDIS_URL,
    maxRetriesPerRequest: null,
  };
  const push = new Queue<PushJobData>(QUEUE_NAMES.push, { connection });
  const openFda = new Queue<OpenFdaJobData>(QUEUE_NAMES.openFda, { connection });
  const pdf = new Queue<PdfJobData>(QUEUE_NAMES.pdf, { connection });
  const digest = new Queue<DigestJobData>(QUEUE_NAMES.digest, { connection });
  return {
    push,
    openFda,
    pdf,
    digest,
    async close() {
      await Promise.all([push.close(), openFda.close(), pdf.close(), digest.close()]);
    },
  };
}
