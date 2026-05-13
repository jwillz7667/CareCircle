import { Worker, type Job } from 'bullmq';
import { createPool } from '@carecircle/db';
import { createLogger } from '@carecircle/shared';
import { loadConfig } from './config.js';
import {
  QUEUE_NAMES,
  buildConnection,
  createQueues,
  type DigestJobData,
  type OpenFdaJobData,
  type PdfJobData,
  type PushJobData,
} from './queues.js';
import { runPushJob } from './jobs/push.js';
import { runOpenFdaJob } from './jobs/openFda.js';
import { runPdfJob } from './jobs/pdf.js';
import { runDigestJob } from './jobs/digest.js';
import { createMinioClient } from './services/minio.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const logger = createLogger({ level: config.LOG_LEVEL, name: 'carecircle-worker' });
  const pool = createPool({
    connectionString: config.DATABASE_URL,
    applicationName: 'cc-worker',
  });
  const connection = buildConnection(config.REDIS_URL);
  const queues = createQueues(connection);
  const minio = createMinioClient(config);

  const pushWorker = new Worker<PushJobData>(
    QUEUE_NAMES.push,
    async (job: Job<PushJobData>) => runPushJob(job.data, { pool, config, logger }),
    { connection, concurrency: 8 },
  );
  const openFdaWorker = new Worker<OpenFdaJobData>(
    QUEUE_NAMES.openFda,
    async (job: Job<OpenFdaJobData>) => runOpenFdaJob(job.data, { config, logger }),
    { connection, concurrency: 4 },
  );
  const pdfWorker = new Worker<PdfJobData>(
    QUEUE_NAMES.pdf,
    async (job: Job<PdfJobData>) => runPdfJob(job.data, { pool, config, logger, minio }),
    { connection, concurrency: 2 },
  );
  const digestWorker = new Worker<DigestJobData>(
    QUEUE_NAMES.digest,
    async (job: Job<DigestJobData>) =>
      runDigestJob(job.data, { pool, logger, pushQueue: queues.push }),
    { connection, concurrency: 4 },
  );

  const all: Worker[] = [pushWorker, openFdaWorker, pdfWorker, digestWorker];
  for (const worker of all) {
    worker.on('failed', (job, err) => {
      logger.error({ jobId: job?.id, name: job?.name, err }, 'job failed');
    });
    worker.on('completed', (job) => {
      logger.info({ jobId: job.id, name: job.name }, 'job completed');
    });
  }

  logger.info({ queues: Object.values(QUEUE_NAMES) }, 'carecircle worker started');

  const shutdown = async (signal: string): Promise<void> => {
    logger.info({ signal }, 'worker shutting down');
    await Promise.all(all.map((w) => w.close()));
    await queues.closeAll();
    await pool.end();
    process.exit(0);
  };
  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('worker failed to start', err);
  process.exit(1);
});
