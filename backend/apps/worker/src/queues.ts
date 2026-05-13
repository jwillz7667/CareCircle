import { Queue, type ConnectionOptions } from 'bullmq';

export const QUEUE_NAMES = {
  push: 'cc.push',
  openFda: 'cc.openfda',
  pdf: 'cc.pdf',
  digest: 'cc.digest',
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

export function buildConnection(redisUrl: string): ConnectionOptions {
  return { url: redisUrl, maxRetriesPerRequest: null };
}

export function createQueues(connection: ConnectionOptions): {
  push: Queue<PushJobData>;
  openFda: Queue<OpenFdaJobData>;
  pdf: Queue<PdfJobData>;
  digest: Queue<DigestJobData>;
  closeAll: () => Promise<void>;
} {
  const push = new Queue<PushJobData>(QUEUE_NAMES.push, { connection });
  const openFda = new Queue<OpenFdaJobData>(QUEUE_NAMES.openFda, { connection });
  const pdf = new Queue<PdfJobData>(QUEUE_NAMES.pdf, { connection });
  const digest = new Queue<DigestJobData>(QUEUE_NAMES.digest, { connection });
  return {
    push,
    openFda,
    pdf,
    digest,
    async closeAll() {
      await Promise.all([push.close(), openFda.close(), pdf.close(), digest.close()]);
    },
  };
}
