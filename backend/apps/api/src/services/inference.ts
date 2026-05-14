/**
 * Cloud entity extractor for iOS clients that can't run Foundation Models
 * on-device (iOS < 26). Receives a PHI-redacted transcript, returns the
 * same JSON shape the on-device extractor produces. Default backend is
 * OpenAI's chat completions endpoint with strict structured output.
 *
 * PHI guarantee: every caller must redact recipient + caregiver names
 * before reaching this service. The service never logs prompt content;
 * only sizes, durations, and model identifiers.
 */
import { randomUUID } from 'node:crypto';
import type { Logger } from '@carecircle/shared';
import {
  extractedEntitiesSchema,
  upstreamError,
  type ExtractedEntitiesT,
  type ExtractionConfidenceT,
} from '@carecircle/shared';
import type { Config } from '../config.js';

export type ExtractInput = {
  redactedTranscript: string;
  locale?: string;
};

export type ExtractResult = {
  entities: ExtractedEntitiesT;
  model: string;
  durationMs: number;
};

export interface InferenceService {
  readonly isEnabled: boolean;
  readonly model: string;
  extract(input: ExtractInput): Promise<ExtractResult>;
}

type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string; signal: AbortSignal },
) => Promise<{ ok: boolean; status: number; text(): Promise<string>; json(): Promise<unknown> }>;

export type CreateInferenceOptions = {
  fetchFn?: FetchLike;
};

const SYSTEM_INSTRUCTIONS = [
  'You extract structured care entities from a single caregiver note.',
  'The note is about a senior whose name has been replaced with [RECIPIENT].',
  'Caregiver names appear as [CAREGIVER_n].',
  'Be conservative: only include items the note clearly mentions.',
  'Do not invent doses, times, or providers.',
  'If the note is small talk or unrelated to care, return empty arrays and an empty summary.',
].join(' ');

const USER_PROMPT_PREFIX = [
  'Pull out the following from this caregiver note:',
  '- medications (name + dose/instructions if mentioned)',
  '- vitals (blood pressure, glucose, weight, temperature, oxygen, pulse)',
  '- appointments (provider/title + time if mentioned)',
  '- meals (what was eaten, how much)',
  '- symptoms (pain, mood, sleep, energy, falls)',
  '- generalNotes (anything else clinically relevant)',
  'Set confidence to high only when the note states the value verbatim.',
  '',
  'Note:',
  '',
].join('\n');

const RESPONSE_JSON_SCHEMA = {
  name: 'extracted_entities',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: [
      'medications',
      'vitals',
      'appointments',
      'meals',
      'symptoms',
      'generalNotes',
      'summary',
    ],
    properties: {
      medications: { type: 'array', items: { $ref: '#/$defs/entity' } },
      vitals: { type: 'array', items: { $ref: '#/$defs/entity' } },
      appointments: { type: 'array', items: { $ref: '#/$defs/entity' } },
      meals: { type: 'array', items: { $ref: '#/$defs/entity' } },
      symptoms: { type: 'array', items: { $ref: '#/$defs/entity' } },
      generalNotes: { type: 'array', items: { $ref: '#/$defs/entity' } },
      summary: { type: ['string', 'null'] },
    },
    $defs: {
      entity: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'details', 'confidence'],
        properties: {
          name: { type: 'string' },
          details: { type: ['string', 'null'] },
          confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
        },
      },
    },
  },
} as const;

type RawEntity = {
  name: string;
  details: string | null;
  confidence: ExtractionConfidenceT;
};

type RawEntities = {
  medications: RawEntity[];
  vitals: RawEntity[];
  appointments: RawEntity[];
  meals: RawEntity[];
  symptoms: RawEntity[];
  generalNotes: RawEntity[];
  summary: string | null;
};

type ChatCompletionResponse = {
  choices?: Array<{
    message?: { content?: string | null };
    finish_reason?: string;
  }>;
  error?: { message?: string; type?: string };
};

export function createInferenceService(
  config: Config,
  logger: Logger,
  opts: CreateInferenceOptions = {},
): InferenceService {
  const fetchFn = (opts.fetchFn ?? (globalThis.fetch as unknown as FetchLike)) as FetchLike;
  const isEnabled = config.INFERENCE_ENABLED && Boolean(config.OPENAI_API_KEY);

  async function extract(input: ExtractInput): Promise<ExtractResult> {
    if (!isEnabled) {
      throw upstreamError('Inference is disabled');
    }
    const apiKey = config.OPENAI_API_KEY;
    if (!apiKey) {
      throw upstreamError('OPENAI_API_KEY is not configured');
    }

    const trimmed = input.redactedTranscript.trim();
    if (trimmed.length === 0) {
      throw upstreamError('Transcript is empty after trim');
    }

    const truncated = trimmed.slice(0, config.INFERENCE_PROMPT_CHAR_LIMIT);
    const userPrompt = USER_PROMPT_PREFIX + truncated;

    const requestBody = {
      model: config.OPENAI_MODEL,
      temperature: 0,
      max_tokens: 1_500,
      messages: [
        { role: 'system', content: SYSTEM_INSTRUCTIONS },
        { role: 'user', content: userPrompt },
      ],
      response_format: { type: 'json_schema', json_schema: RESPONSE_JSON_SCHEMA },
    };

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), config.INFERENCE_TIMEOUT_MS);
    const startedAt = Date.now();

    let response: Awaited<ReturnType<FetchLike>>;
    try {
      response = await fetchFn(`${config.OPENAI_BASE_URL.replace(/\/$/, '')}/chat/completions`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify(requestBody),
        signal: controller.signal,
      });
    } catch (err) {
      const isAbort =
        (err as { name?: string })?.name === 'AbortError' ||
        controller.signal.aborted;
      logger.warn(
        {
          err: isAbort ? 'timeout' : err,
          model: config.OPENAI_MODEL,
          durationMs: Date.now() - startedAt,
        },
        'inference fetch failed',
      );
      throw upstreamError(isAbort ? 'Inference timed out' : 'Inference request failed');
    } finally {
      clearTimeout(timer);
    }

    if (!response.ok) {
      let detail = '';
      try {
        detail = await response.text();
      } catch {
        // ignore
      }
      logger.warn(
        {
          status: response.status,
          model: config.OPENAI_MODEL,
          durationMs: Date.now() - startedAt,
          detail: detail.slice(0, 500),
        },
        'inference upstream non-2xx',
      );
      throw upstreamError(`Upstream returned ${response.status}`);
    }

    let parsed: ChatCompletionResponse;
    try {
      parsed = (await response.json()) as ChatCompletionResponse;
    } catch (err) {
      logger.warn({ err, model: config.OPENAI_MODEL }, 'inference response not JSON');
      throw upstreamError('Upstream response not JSON');
    }

    const content = parsed.choices?.[0]?.message?.content;
    if (!content) {
      logger.warn(
        { model: config.OPENAI_MODEL, finishReason: parsed.choices?.[0]?.finish_reason },
        'inference response had no content',
      );
      throw upstreamError('Upstream returned no content');
    }

    let raw: RawEntities;
    try {
      raw = JSON.parse(content) as RawEntities;
    } catch (err) {
      logger.warn({ err, model: config.OPENAI_MODEL }, 'inference content not JSON');
      throw upstreamError('Upstream content was not valid JSON');
    }

    const entities = toExtractedEntities(raw);
    // Validate against schema as a safety net; this is the same shape the
    // iOS client decodes, so a mismatch here would surface as a client
    // decode error anyway.
    const validated = extractedEntitiesSchema.parse(entities);
    const durationMs = Date.now() - startedAt;
    return { entities: validated, model: config.OPENAI_MODEL, durationMs };
  }

  return {
    isEnabled,
    model: config.OPENAI_MODEL,
    extract,
  };
}

function toExtractedEntities(raw: RawEntities): ExtractedEntitiesT {
  const summary = typeof raw.summary === 'string' ? raw.summary.trim() : null;
  return {
    medications: mapEntities(raw.medications),
    vitals: mapEntities(raw.vitals),
    appointments: mapEntities(raw.appointments),
    meals: mapEntities(raw.meals),
    symptoms: mapEntities(raw.symptoms),
    generalNotes: mapEntities(raw.generalNotes),
    summary: summary && summary.length > 0 ? summary.slice(0, 280) : null,
  };
}

function mapEntities(items: RawEntity[] | undefined): ExtractedEntitiesT['medications'] {
  if (!Array.isArray(items)) {
    return [];
  }
  return items
    .filter((it) => typeof it?.name === 'string' && it.name.trim().length > 0)
    .slice(0, 50)
    .map((it) => ({
      id: randomUUID(),
      name: it.name.trim().slice(0, 200),
      details:
        typeof it.details === 'string' && it.details.trim().length > 0
          ? it.details.trim().slice(0, 500)
          : null,
      confidence: normalizeConfidence(it.confidence),
    }));
}

function normalizeConfidence(value: unknown): ExtractionConfidenceT {
  if (value === 'low' || value === 'medium' || value === 'high') {
    return value;
  }
  return 'medium';
}
