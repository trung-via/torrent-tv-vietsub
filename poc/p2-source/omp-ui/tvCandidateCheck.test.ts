import { describe, expect, it } from 'vitest';
import {
  inspectP2Reported, inspectP2ReportedDetail, p2TitleClaims4k,
  p2UnknownReasonLabel, P2_EXAMPLE_CRITERIA, rankP2Reported,
} from '../../src/sources/tvCandidateCheck';
import type { SourceResult } from '../../src/sources/types';

function row(part: Partial<SourceResult> = {}): SourceResult {
  return {
    Title: 'Legal.Test.Fixture.2160p', Categories: '', Size: '10 GB',
    CreateDate: '', Tracker: 'test-fixture-tracker', Link: '',
    Magnet: '', Hash: '', Peer: 9, Seed: 350, source: 'ts-torznab',
    sizeBytes: 10_000_000_000, ...part,
  };
}

describe('P2 TV: reported 6–15 GB, release-title 4K hint, highest reported seeds', () => {
  it('uses decimal 6 GB to 15 GB with inclusive endpoints, never a 300-seed floor', () => {
    expect(P2_EXAMPLE_CRITERIA).toEqual({ minBytes: 6_000_000_000, maxBytes: 15_000_000_000 });
    expect(inspectP2Reported(row({ sizeBytes: 6_000_000_000, Seed: 0 }))).toBe('reported-match');
    expect(inspectP2Reported(row({ sizeBytes: 15_000_000_000, Seed: 1 }))).toBe('reported-match');
    expect(inspectP2Reported(row({ sizeBytes: 5_999_999_999, Seed: 900 }))).toBe('reported-mismatch');
    expect(inspectP2Reported(row({ sizeBytes: 15_000_000_001, Seed: 900 }))).toBe('reported-mismatch');
  });

  it('recognizes bounded 4K/2160p/UHD title hints but never validates actual pixels', () => {
    for (const title of ['Film.2160p.HEVC', 'Legal Film 4K HDR', 'Film_UHD_WEB', '[4K] Sample', 'film 2160']) {
      expect(p2TitleClaims4k(title)).toBe(true);
      expect(inspectP2Reported(row({ Title: title }))).toBe('reported-match');
    }
    for (const title of ['Film.1080p.HEVC', 'Film.720p', 'Film.1440p', 'Film.4KID', 'Film.2160px']) {
      expect(p2TitleClaims4k(title)).toBe(false);
    }
    expect(inspectP2Reported(row({ Title: 'Film.1080p' }))).toBe('reported-mismatch');
    expect(inspectP2ReportedDetail(row({ Title: 'Film.1080p' })).reason).toBe('reported-non4k-title');
    expect(inspectP2Reported(row({ Title: 'Film.No.Resolution.Info' }))).toBe('unknown');
    expect(inspectP2ReportedDetail(row({ Title: 'Film.No.Resolution.Info' })).reason)
      .toBe('resolution-not-claimed');
    expect(inspectP2Reported(row({ Title: 'Film.2160p.1080p' }))).toBe('unknown');
    expect(inspectP2Reported(row({ Title: 'Film.4KID' }))).toBe('unknown');
  });

  it('does not treat numbers in an untrusted title as measured media properties', () => {
    expect(inspectP2Reported(row({ Title: 'Film.2160p', sizeBytes: undefined }))).toBe('unknown');
    expect(inspectP2Reported(row({ Title: 'Film.2160p', Seed: NaN }))).toBe('unknown');
    expect(inspectP2Reported(row({ Title: 'Film.2160p', Seed: -1 }))).toBe('unknown');
    expect(inspectP2Reported(row({ Title: 'Film.2160p', Seed: 2.2 }))).toBe('unknown');
    expect(inspectP2Reported(row({ Title: 'Film.2160p.VI.AAC', sizeBytes: 50_000_000_000 })))
      .toBe('reported-mismatch');
  });

  it('evaluates only primary pinned TorrServer Rutor and Torznab adapters', () => {
    expect(inspectP2Reported(row({ source: 'ts-rutor', Tracker: '', Seed: 9 }))).toBe('reported-match');
    expect(inspectP2Reported(row({ source: 'ts-rutor', Tracker: '', sizeBytes: 44_600_000_000 })))
      .toBe('reported-mismatch');
    expect(inspectP2Reported(row({ source: 'other', sources: ['ts-rutor'] }))).toBe('unknown');
    expect(inspectP2Reported(row({ source: 'other', sources: ['ts-torznab'] }))).toBe('unknown');
    expect(inspectP2Reported(row({ source: 'ts-rutor-clone' }))).toBe('unknown');
    expect(inspectP2Reported(row({ source: 'ts-torznab', Tracker: '' }))).toBe('unknown');
  });

  it('provides only safe static UNKNOWN explanations', () => {
    const unsupported = inspectP2ReportedDetail(row({ source: 'other', Tracker: 'private-tracker-secret' }));
    expect(unsupported).toEqual({ status: 'unknown', reason: 'source-not-supported' });
    expect(p2UnknownReasonLabel(unsupported.reason)).toBe('nguồn chưa hỗ trợ');
    expect(inspectP2ReportedDetail(row({ Tracker: '' })).reason).toBe('torznab-tracker-missing');
    expect(inspectP2ReportedDetail(row({ sizeBytes: undefined })).reason).toBe('size-unverified');
    expect(inspectP2ReportedDetail(row({ Seed: NaN })).reason).toBe('seeds-unverified');
    expect(p2UnknownReasonLabel('resolution-not-claimed')).toBe('chưa rõ 4K theo tên');
    expect(p2UnknownReasonLabel(unsupported.reason)).not.toContain('private-tracker');
  });

  it('rejects invalid size bounds without silently broadening matches', () => {
    expect(inspectP2Reported(row(), { ...P2_EXAMPLE_CRITERIA, maxBytes: 0 })).toBe('unknown');
    expect(inspectP2Reported(row(), { ...P2_EXAMPLE_CRITERIA, minBytes: 20_000_000_000 }))
      .toBe('unknown');
    expect(inspectP2Reported(row(), { ...P2_EXAMPLE_CRITERIA, maxBytes: NaN })).toBe('unknown');
  });

  it('ranks matched 4K + size first, then descending reported seeds; keeps all rows', () => {
    const match350 = row({ Title: 'Fixture.2160p.seed350', Seed: 350 });
    const match9 = row({ Title: 'Fixture.4K.seed9', Seed: 9, source: 'ts-rutor', Tracker: '' });
    const match1000 = row({ Title: 'Fixture.UHD.seed1000', Seed: 1000 });
    const no4k = row({ Title: 'Fixture.no-resolution.seed9000', Seed: 9000 });
    const outside = row({ Title: 'Fixture.2160p.24GB.seed12000', sizeBytes: 24_000_000_000, Seed: 12000 });
    const initial = [outside, match9, no4k, match350, match1000];
    const ranked = rankP2Reported(initial);
    expect(ranked.map(r => r.Title)).toEqual([
      match1000.Title, match350.Title, match9.Title, no4k.Title, outside.Title,
    ]);
    expect(initial[0]).toBe(outside);
    expect(ranked).toHaveLength(initial.length);
  });

  it('is stable on equal reported seeds and does not promote untrusted high-seed rows', () => {
    const a = row({ Title: 'A.4K', Seed: 500 });
    const b = row({ Title: 'B.2160p', Seed: 500 });
    const unknown = row({ Title: 'C.4K', source: 'untrusted', Seed: 9900 });
    const bad = row({ Title: 'D.1080p', Seed: 11000 });
    expect(rankP2Reported([b, bad, unknown, a]).map(r => r.Title))
      .toEqual(['B.2160p', 'A.4K', 'C.4K', 'D.1080p']);
  });

  it('keeps UNKNOWN for genuinely missing metadata and sorts known seeds before missing', () => {
    const seedMissing = row({ Title: 'A.4K', Seed: NaN });
    const sizeMissing = row({ Title: 'B.4K', sizeBytes: undefined, Seed: 1000 });
    const match = row({ Title: 'C.4K', Seed: 0 });
    expect(rankP2Reported([seedMissing, sizeMissing, match]).map(r => r.Title))
      .toEqual(['C.4K', 'B.4K', 'A.4K']);
  });
});
