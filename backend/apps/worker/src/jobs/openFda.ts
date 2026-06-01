import { request } from 'undici';
import type { Logger } from '@carecircle/shared';
import type { Config } from '../config.js';
import type { OpenFdaJobData } from '../queues.js';

const BASE = 'https://api.fda.gov/drug/label.json';

export type OpenFdaResult = {
  brandName?: string;
  genericName?: string;
  warnings?: string[];
  interactions?: string[];
  contraindications?: string[];
  raw?: unknown;
};

export async function runOpenFdaJob(
  data: OpenFdaJobData,
  ctx: { config: Config; logger: Logger },
): Promise<OpenFdaResult> {
  const { config, logger } = ctx;
  const filters: string[] = [];
  if (data.rxcui) {
    filters.push(`openfda.rxcui:${data.rxcui}`);
  }
  if (data.ndc) {
    filters.push(`openfda.product_ndc:${data.ndc}`);
  }
  if (data.brandName) {
    // Strip embedded quotes so the phrase query can't be broken out of; let
    // URLSearchParams do the one and only percent-encoding pass below.
    filters.push(`openfda.brand_name:"${data.brandName.replace(/"/g, '')}"`);
  }
  if (filters.length === 0) {
    throw new Error('openFda job requires rxcui, ndc, or brandName');
  }
  const params = new URLSearchParams();
  // Join with a real " AND ": URLSearchParams encodes the spaces to "+", which
  // is exactly openFDA's term separator. The previous "+AND+" literal was
  // re-encoded to "%2B" (a literal plus), corrupting the query.
  params.set('search', filters.join(' AND '));
  params.set('limit', '1');
  if (config.OPENFDA_API_KEY) {
    params.set('api_key', config.OPENFDA_API_KEY);
  }
  const url = `${BASE}?${params.toString()}`;
  const response = await request(url, { method: 'GET' });
  if (response.statusCode === 404) {
    logger.info({ url }, 'openFDA no match');
    return {};
  }
  if (response.statusCode >= 400) {
    const text = await response.body.text().catch(() => '');
    throw new Error(`openFDA ${response.statusCode}: ${text}`);
  }
  const json = (await response.body.json()) as {
    results?: Array<{
      openfda?: { brand_name?: string[]; generic_name?: string[] };
      warnings?: string[];
      drug_interactions?: string[];
      contraindications?: string[];
    }>;
  };
  const hit = json.results?.[0];
  return {
    brandName: hit?.openfda?.brand_name?.[0],
    genericName: hit?.openfda?.generic_name?.[0],
    warnings: hit?.warnings,
    interactions: hit?.drug_interactions,
    contraindications: hit?.contraindications,
  };
}
