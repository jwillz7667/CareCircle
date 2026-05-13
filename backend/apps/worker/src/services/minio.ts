import { Client as MinioClient } from 'minio';
import type { Config } from '../config.js';

export function createMinioClient(config: Config): MinioClient {
  return new MinioClient({
    endPoint: config.MINIO_ENDPOINT,
    port: config.MINIO_PORT,
    useSSL: config.MINIO_USE_SSL,
    accessKey: config.MINIO_ACCESS_KEY,
    secretKey: config.MINIO_SECRET_KEY,
    region: config.MINIO_REGION,
  });
}
