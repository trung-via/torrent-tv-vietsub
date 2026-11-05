// P2-SOURCE.3: UI-only inspection of Torznab's reported size and seed counts.
// Loaded into pinned OMP src/sources/ by a guarded overlay, never a source grant.
// No rights inference, media probing, peer connection, download or auto-add.
import type { SourceResult } from './types';

export type P2MetadataStatus = 'reported-match' | 'reported-mismatch' | 'unknown';
export interface P2MetadataCriteria {
  minBytes: number;
  maxBytes: number;
  minReportedSeeds: number;
}

/** Explicit sample from the North Star. GB here means decimal billion bytes. */
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

/** Snapshot-only evaluation. Even a match is NOT permission to fetch the torrent. */
export function inspectP2Reported(
  r: Pick<SourceResult, 'source' | 'Tracker' | 'sizeBytes' | 'Seed'>,
  criteria: P2MetadataCriteria = P2_EXAMPLE_CRITERIA,
): P2MetadataStatus {
  // The corresponding offline contract is limited to the pinned TorrServer
  // Torznab adapter. Merged secondary sources must not confer source identity.
  if (r.source !== 'ts-torznab' || typeof r.Tracker !== 'string' || !r.Tracker.trim()) return 'unknown';
  if (!(positiveInteger(criteria.minBytes) && positiveInteger(criteria.maxBytes)
    && criteria.minBytes <= criteria.maxBytes && nonnegativeInteger(criteria.minReportedSeeds))) return 'unknown';
  const sizeKnown = positiveInteger(r.sizeBytes);
  const seedsKnown = nonnegativeInteger(r.Seed);
  if (sizeKnown && (r.sizeBytes! < criteria.minBytes || r.sizeBytes! > criteria.maxBytes)) return 'reported-mismatch';
  if (seedsKnown && r.Seed < criteria.minReportedSeeds) return 'reported-mismatch';
  if (!sizeKnown || !seedsKnown) return 'unknown';
  return 'reported-match';
}

/** A stable copy. While search streams, the caller should NOT reorder rows. */
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
