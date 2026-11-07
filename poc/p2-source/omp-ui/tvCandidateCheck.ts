// P2-SOURCE.5: opt-in ranking of reported size, release-title 4K hints and seeds.
// Search result metadata never verifies media dimensions, live peers or rights.
import type { SourceResult } from './types';

export type P2MetadataStatus = 'reported-match' | 'reported-mismatch' | 'unknown';
export type P2MetadataReason =
  | 'source-not-supported'
  | 'torznab-tracker-missing'
  | 'criteria-invalid'
  | 'size-unverified'
  | 'seeds-unverified'
  | 'resolution-not-claimed'
  | 'reported-non4k-title'
  | 'reported-outside-range'
  | 'reported-match';

export interface P2MetadataAssessment {
  status: P2MetadataStatus;
  reason: P2MetadataReason;
}

export interface P2MetadataCriteria {
  minBytes: number;
  maxBytes: number;
}

/** GB is decimal; no minimum seeder threshold. High reported seeds rank first. */
export const P2_EXAMPLE_CRITERIA: P2MetadataCriteria = {
  minBytes: 6_000_000_000,
  maxBytes: 15_000_000_000,
};

function positiveInteger(value: unknown): value is number {
  return typeof value === 'number' && isFinite(value) && Math.floor(value) === value && value > 0;
}

function nonnegativeInteger(value: unknown): value is number {
  return typeof value === 'number' && isFinite(value) && Math.floor(value) === value && value >= 0;
}

const unknown = (reason: P2MetadataReason): P2MetadataAssessment => ({ status: 'unknown', reason });

/**
 * Only recognize 4K/2160p/UHD *claims in release titles*, never actual dimensions.
 * Boundaries exclude false positives such as 4KID or 2160px; no guess from
 * title quality rankings or unrelated fields. Unlabeled is UNKNOWN, not 1080p.
 */
export function p2TitleClaims4k(title: unknown): boolean {
  return typeof title === 'string' &&
    /(?:^|[^a-z0-9])(?:2160p?|4k|uhd)(?=$|[^a-z0-9])/i.test(title);
}

function p2TitleClaimsLowerResolution(title: unknown): boolean {
  return typeof title === 'string' &&
    /(?:^|[^a-z0-9])(?:1440p?|1080p?|720p?|480p?)(?=$|[^a-z0-9])/i.test(title);
}

/**
 * Evaluate only the two pinned primary TorrServer adapters from OMP registry.ts.
 * Torznab requires a nonblank tracker display field; Rutor has a fixed source id.
 * Secondary merged sources cannot grant trust. Numeric size/seed and 4K hints
 * are source-reported/claimed, not media probes or content authorization.
 */
export function inspectP2ReportedDetail(
  r: Pick<SourceResult, 'source' | 'Tracker' | 'sizeBytes' | 'Seed' | 'Title'>,
  criteria: P2MetadataCriteria = P2_EXAMPLE_CRITERIA,
): P2MetadataAssessment {
  if (r.source !== 'ts-rutor' && r.source !== 'ts-torznab') return unknown('source-not-supported');
  if (r.source === 'ts-torznab' && (typeof r.Tracker !== 'string' || !r.Tracker.trim())) {
    return unknown('torznab-tracker-missing');
  }
  if (!(positiveInteger(criteria.minBytes) && positiveInteger(criteria.maxBytes)
    && criteria.minBytes <= criteria.maxBytes)) {
    return unknown('criteria-invalid');
  }
  const sizeKnown = positiveInteger(r.sizeBytes);
  const seedsKnown = nonnegativeInteger(r.Seed);

  if (sizeKnown && (r.sizeBytes! < criteria.minBytes || r.sizeBytes! > criteria.maxBytes)) {
    return { status: 'reported-mismatch', reason: 'reported-outside-range' };
  }
  if (!sizeKnown) return unknown('size-unverified');

  // 4K in a title is only a hint. A release naming both 4K and 1080p
  // is ambiguous, so do not certify a match solely from that title.
  const claims4k = p2TitleClaims4k(r.Title);
  const claimsOther = p2TitleClaimsLowerResolution(r.Title);
  if (claims4k && claimsOther) return unknown('resolution-not-claimed');
  if (!claims4k && claimsOther) {
    return { status: 'reported-mismatch', reason: 'reported-non4k-title' };
  }
  if (!claims4k) return unknown('resolution-not-claimed');
  if (!seedsKnown) return unknown('seeds-unverified');
  return { status: 'reported-match', reason: 'reported-match' };
}

export function inspectP2Reported(
  r: Pick<SourceResult, 'source' | 'Tracker' | 'sizeBytes' | 'Seed' | 'Title'>,
  criteria: P2MetadataCriteria = P2_EXAMPLE_CRITERIA,
): P2MetadataStatus {
  return inspectP2ReportedDetail(r, criteria).status;
}

/** Static diagnostics only: no raw tracker, title, magnet, token or link. */
export function p2UnknownReasonLabel(reason: P2MetadataReason): string {
  if (reason === 'source-not-supported') return 'nguồn chưa hỗ trợ';
  if (reason === 'torznab-tracker-missing') return 'thiếu tracker';
  if (reason === 'criteria-invalid') return 'tiêu chí không hợp lệ';
  if (reason === 'size-unverified') return 'thiếu kích thước';
  if (reason === 'seeds-unverified') return 'thiếu seed báo cáo';
  if (reason === 'resolution-not-claimed') return 'chưa rõ 4K theo tên';
  return 'metadata chưa xác minh';
}

/** Match (6–15 GB + 4K claimed) first, highest reported seeds within each class.
 * Never discard rows, mutate source results or reorder while search is streaming.
 */
export function rankP2Reported<T extends Pick<SourceResult, 'source' | 'Tracker' | 'sizeBytes' | 'Seed' | 'Title'>>(
  rows: T[], criteria: P2MetadataCriteria = P2_EXAMPLE_CRITERIA,
): T[] {
  const priority: { [k in P2MetadataStatus]: number } = {
    'reported-match': 0, unknown: 1, 'reported-mismatch': 2,
  };
  return rows.map((r, i) => ({
    r, i,
    priority: priority[inspectP2Reported(r, criteria)],
    seeds: nonnegativeInteger(r.Seed) ? r.Seed : -1,
  }))
    .sort((a, b) => a.priority - b.priority || b.seeds - a.seeds || a.i - b.i)
    .map((x) => x.r);
}
