// P2-SOURCE.4: bounded, UI-only assessment of reported size and seed metadata.
// Never confers source authorization, verifies live peers/media, or adds torrents.
import type { SourceResult } from './types';

export type P2MetadataStatus = 'reported-match' | 'reported-mismatch' | 'unknown';
export type P2MetadataReason =
  | 'source-not-supported'
  | 'torznab-tracker-missing'
  | 'criteria-invalid'
  | 'size-unverified'
  | 'seeds-unverified'
  | 'reported-outside-range'
  | 'reported-match';

export interface P2MetadataAssessment {
  status: P2MetadataStatus;
  reason: P2MetadataReason;
}

export interface P2MetadataCriteria {
  minBytes: number;
  maxBytes: number;
  minReportedSeeds: number;
}

/** GB is decimal. Reported seed counts are not connected/live peers. */
export const P2_EXAMPLE_CRITERIA: P2MetadataCriteria = {
  minBytes: 8_000_000_000,
  maxBytes: 12_000_000_000,
  minReportedSeeds: 300,
};

function positiveInteger(value: unknown): value is number {
  return typeof value === 'number' && isFinite(value) && Math.floor(value) === value && value > 0;
}

function nonnegativeInteger(value: unknown): value is number {
  return typeof value === 'number' && isFinite(value) && Math.floor(value) === value && value >= 0;
}

const unknown = (reason: P2MetadataReason): P2MetadataAssessment => ({ status: 'unknown', reason });

/**
 * Only the two pinned TorrServer adapters from OMP registry.ts can be evaluated:
 * ts-torznab needs a tracker display field; ts-rutor carries a fixed source id.
 * Other built-in sources, phone results, or secondary merged 'sources' stay UNKNOWN.
 * Neither the result's tracker display field nor its title grants legal access.
 */
export function inspectP2ReportedDetail(
  r: Pick<SourceResult, 'source' | 'Tracker' | 'sizeBytes' | 'Seed'>,
  criteria: P2MetadataCriteria = P2_EXAMPLE_CRITERIA,
): P2MetadataAssessment {
  if (r.source !== 'ts-rutor' && r.source !== 'ts-torznab') return unknown('source-not-supported');
  if (r.source === 'ts-torznab' && (typeof r.Tracker !== 'string' || !r.Tracker.trim())) {
    return unknown('torznab-tracker-missing');
  }
  if (!(positiveInteger(criteria.minBytes) && positiveInteger(criteria.maxBytes)
    && criteria.minBytes <= criteria.maxBytes && nonnegativeInteger(criteria.minReportedSeeds))) {
    return unknown('criteria-invalid');
  }
  const sizeKnown = positiveInteger(r.sizeBytes);
  const seedsKnown = nonnegativeInteger(r.Seed);

  // A known mismatch is actionable even if the other numeric field is missing.
  if ((sizeKnown && (r.sizeBytes! < criteria.minBytes || r.sizeBytes! > criteria.maxBytes))
    || (seedsKnown && r.Seed < criteria.minReportedSeeds)) {
    return { status: 'reported-mismatch', reason: 'reported-outside-range' };
  }
  if (!sizeKnown) return unknown('size-unverified');
  if (!seedsKnown) return unknown('seeds-unverified');
  return { status: 'reported-match', reason: 'reported-match' };
}

/** Compatible status-only interface for the existing ranking consumer. */
export function inspectP2Reported(
  r: Pick<SourceResult, 'source' | 'Tracker' | 'sizeBytes' | 'Seed'>,
  criteria: P2MetadataCriteria = P2_EXAMPLE_CRITERIA,
): P2MetadataStatus {
  return inspectP2ReportedDetail(r, criteria).status;
}

/** Static labels only: do not show raw tracker names, tokens or result URLs. */
export function p2UnknownReasonLabel(reason: P2MetadataReason): string {
  if (reason === 'source-not-supported') return 'nguồn chưa hỗ trợ';
  if (reason === 'torznab-tracker-missing') return 'thiếu tracker';
  if (reason === 'criteria-invalid') return 'tiêu chí không hợp lệ';
  if (reason === 'size-unverified') return 'thiếu kích thước';
  if (reason === 'seeds-unverified') return 'thiếu seed báo cáo';
  return 'metadata chưa xác minh';
}

/** Stable copy. While streaming, the caller does not reorder result rows. */
export function rankP2Reported<T extends Pick<SourceResult, 'source' | 'Tracker' | 'sizeBytes' | 'Seed'>>(
  rows: T[], criteria: P2MetadataCriteria = P2_EXAMPLE_CRITERIA,
): T[] {
  const priority: { [k in P2MetadataStatus]: number } = {
    'reported-match': 0, unknown: 1, 'reported-mismatch': 2,
  };
  return rows.map((r, i) => ({ r, i, p: priority[inspectP2Reported(r, criteria)] }))
    .sort((a, b) => a.p - b.p || a.i - b.i)
    .map((x) => x.r);
}
