import { describe, expect, it } from 'vitest';
import { inspectP2Reported, P2_EXAMPLE_CRITERIA, rankP2Reported } from './tvCandidateCheck';
import type { SourceResult } from './types';

function row(part: Partial<SourceResult> = {}): SourceResult {
  return {
    Title: 'Test.Title.1440p.Vietnamese', Categories: '', Size: '10 GB',
    CreateDate: '', Tracker: 'approved-fixture-tracker', Link: '',
    Magnet: '', Hash: '', Peer: 9, Seed: 350, source: 'ts-torznab',
    sizeBytes: 10_000_000_000, ...part,
  };
}

describe('P2 TV reported metadata, not media verification', () => {
  it('marks only reported size and seed match, never verified quality', () => {
    expect(inspectP2Reported(row())).toBe('reported-match');
  });
  it('rejects known size below and above the hard bounds', () => {
    expect(inspectP2Reported(row({ sizeBytes: 7_000_000_000 }))).toBe('reported-mismatch');
    expect(inspectP2Reported(row({ sizeBytes: 13_000_000_000 }))).toBe('reported-mismatch');
  });
  it('rejects an explicitly reported seed count below threshold', () => {
    expect(inspectP2Reported(row({ Seed: 299 }))).toBe('reported-mismatch');
    expect(inspectP2Reported(row({ Seed: 0 }))).toBe('reported-mismatch');
  });
  it('marks missing or invalid size/seed as unknown', () => {
    expect(inspectP2Reported(row({ sizeBytes: undefined }))).toBe('unknown');
    expect(inspectP2Reported(row({ Seed: NaN }))).toBe('unknown');
    expect(inspectP2Reported(row({ Seed: -1 }))).toBe('unknown');
    expect(inspectP2Reported(row({ Seed: 1.2 }))).toBe('unknown');
  });
  it('does not trust results from non Torznab adapters', () => {
    expect(inspectP2Reported(row({ source: 'ts-rutor' }))).toBe('unknown');
    expect(inspectP2Reported(row({ source: 'other', sources: ['ts-torznab'] }))).toBe('unknown');
    expect(inspectP2Reported(row({ Tracker: '' }))).toBe('unknown');
  });
  it('ignores claim in title of 1440p and Vietnamese audio', () => {
    expect(inspectP2Reported(row({ sizeBytes: undefined, Seed: 0, Title: '1440p.VI.AAC' }))).toBe('reported-mismatch');
    expect(inspectP2Reported(row({ sizeBytes: undefined, Seed: 350, Title: '4K.VI.HEVC' }))).toBe('unknown');
  });
  it('rejects invalid criteria rather than widening limits', () => {
    expect(inspectP2Reported(row(), { ...P2_EXAMPLE_CRITERIA, maxBytes: 1 })).toBe('unknown');
    expect(inspectP2Reported(row(), { ...P2_EXAMPLE_CRITERIA, minReportedSeeds: -1 })).toBe('unknown');
  });
  it('ranks results match, unknown, mismatch with stable within-class order', () => {
    const a = row({ Title: 'match-A' });
    const b = row({ Title: 'unknown-B', sizeBytes: undefined });
    const c = row({ Title: 'fail-C', Seed: 20 });
    const d = row({ Title: 'match-D', Seed: 800 });
    const before = [c, b, a, d];
    const ranked = rankP2Reported(before);
    expect(ranked.map(x => x.Title)).toEqual(['match-A', 'match-D', 'unknown-B', 'fail-C']);
    expect(before.map(x => x.Title)).toEqual(['fail-C', 'unknown-B', 'match-A', 'match-D']);
  });
});
