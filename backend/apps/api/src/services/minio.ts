import { Client as MinioClient } from 'minio';
import type { Config } from '../config.js';

export type StorageBucket = 'cc-photos' | 'cc-voice' | 'cc-documents' | 'cc-pdf-exports';

export const BUCKETS: readonly StorageBucket[] = [
  'cc-photos',
  'cc-voice',
  'cc-documents',
  'cc-pdf-exports',
];

const URL_EXPIRY: Record<StorageBucket, number> = {
  'cc-photos': 60 * 60,
  'cc-voice': 60 * 60,
  'cc-documents': 5 * 60,
  'cc-pdf-exports': 24 * 60 * 60,
};

export interface ObjectStorage {
  presignPut(bucket: StorageBucket, objectKey: string, contentType: string): Promise<string>;
  presignGet(bucket: StorageBucket, objectKey: string): Promise<string>;
  ensureBuckets(): Promise<void>;
  deleteObject(bucket: StorageBucket, objectKey: string): Promise<void>;
}

export function createObjectStorage(config: Config): ObjectStorage {
  const client = new MinioClient({
    endPoint: config.MINIO_ENDPOINT,
    port: config.MINIO_PORT,
    useSSL: config.MINIO_USE_SSL,
    accessKey: config.MINIO_ACCESS_KEY,
    secretKey: config.MINIO_SECRET_KEY,
    region: config.MINIO_REGION,
  });

  return {
    async presignPut(bucket, objectKey, _contentType) {
      return await client.presignedPutObject(bucket, objectKey, URL_EXPIRY[bucket]);
    },
    async presignGet(bucket, objectKey) {
      return await client.presignedGetObject(bucket, objectKey, URL_EXPIRY[bucket]);
    },
    async ensureBuckets() {
      for (const bucket of BUCKETS) {
        const exists = await client.bucketExists(bucket).catch(() => false);
        if (!exists) {
          await client.makeBucket(bucket, config.MINIO_REGION);
        }
      }
    },
    async deleteObject(bucket, objectKey) {
      await client.removeObject(bucket, objectKey);
    },
  };
}
