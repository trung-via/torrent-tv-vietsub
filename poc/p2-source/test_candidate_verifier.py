"""Offline P2-SOURCE policy regressions. python -m unittest discover -s poc/p2-source -p 'test_*.py'"""
import unittest

from candidate_verifier import (
    Assessment, Candidate, Criteria, Resolution, SeedKind, SeedObservation,
    Verdict, assess,
)

GB = 1_000_000_000


def c(**kw):
    params = dict(
        opaque_id="test-1", source_id="authorized-adapter",
        source_authorized=True, file_size_bytes=10 * GB,
        width_px=2560, height_px=1440, video_codec="hevc",
        audio_languages=("vi",),
        observations=(SeedObservation(SeedKind.REPORTED, 350, "adapter_snapshot", "2026-11-05T10:00:00Z"),),
    )
    params.update(kw)
    return Candidate(**params)


class CandidateVerificationTests(unittest.TestCase):
    def test_metadata_eligible_but_never_auto_start(self):
        result = assess(c(), Criteria(min_bytes=8 * GB, max_bytes=12 * GB,
                                      resolution=Resolution.P1440, min_seeds=300,
                                      require_audio_vi=True))
        self.assertEqual(result.verdict, Verdict.ELIGIBLE_METADATA)
        self.assertEqual(result.reasons, ("UPSTREAM_CONFIRMATION_STILL_REQUIRED",))
        self.assertEqual(result.seed_observation.kind, SeedKind.REPORTED)

    def test_untrusted_source_always_rejected(self):
        self.assertEqual(assess(c(source_authorized=False), Criteria()).verdict, Verdict.REJECT)

    def test_size_unknown_is_not_guessed_from_title(self):
        x = assess(c(file_size_bytes=None), Criteria(min_bytes=8 * GB))
        self.assertEqual(x.verdict, Verdict.UNKNOWN)

    def test_size_rejects_above_and_below(self):
        req = Criteria(min_bytes=8 * GB, max_bytes=12 * GB)
        self.assertEqual(assess(c(file_size_bytes=7 * GB), req).verdict, Verdict.REJECT)
        self.assertEqual(assess(c(file_size_bytes=13 * GB), req).verdict, Verdict.REJECT)

    def test_1440p_vs_dci2k_explicit_distinction(self):
        x = c(width_px=2048, height_px=1080)
        self.assertEqual(assess(x, Criteria(resolution=Resolution.DCI2K)).verdict,
                         Verdict.ELIGIBLE_METADATA)
        self.assertEqual(assess(x, Criteria(resolution=Resolution.P1440)).verdict,
                         Verdict.REJECT)

    def test_resolution_missing_is_unknown(self):
        self.assertEqual(assess(c(width_px=None), Criteria(resolution=Resolution.P1440)).verdict,
                         Verdict.UNKNOWN)

    def test_reported_seed_cannot_be_replaced_by_connected(self):
        observed = (SeedObservation(SeedKind.CONNECTED, 500, "verified_peer", "2026-11-05T10:00:00Z"),)
        x = assess(c(observations=observed), Criteria(min_seeds=300))
        self.assertEqual(x.verdict, Verdict.UNKNOWN)

    def test_reported_seed_threshold_rejects(self):
        x = assess(c(observations=(
            SeedObservation(SeedKind.REPORTED, 299, "adapter", "2026-11-05T10:00:00Z"),
        )), Criteria(min_seeds=300))
        self.assertEqual(x.verdict, Verdict.REJECT)

    def test_duplicate_seed_snapshots_are_ambiguous(self):
        o = SeedObservation(SeedKind.REPORTED, 1000, "adapter", "2026-11-05T10:00:00Z")
        x = assess(c(observations=(o, o)), Criteria(min_seeds=300))
        self.assertEqual(x.verdict, Verdict.UNKNOWN)

    def test_vi_audio_metadata_gate(self):
        self.assertEqual(assess(c(audio_languages=("en",)), Criteria(require_audio_vi=True)).verdict,
                         Verdict.REJECT)
        self.assertEqual(assess(c(audio_languages=()), Criteria(require_audio_vi=True)).verdict,
                         Verdict.UNKNOWN)

    def test_size_range_inversion_fails_closed(self):
        with self.assertRaises(ValueError):
            Criteria(min_bytes=12 * GB, max_bytes=8 * GB)

    def test_negative_seed_fails_closed(self):
        with self.assertRaises(ValueError):
            SeedObservation(SeedKind.REPORTED, -1, "adapter", "2026-11-05T10:00:00Z")

    def test_invalid_zero_dimensions_fails_closed(self):
        with self.assertRaises(ValueError):
            c(width_px=0)

    def test_untrusted_source_dominates_unknown(self):
        result = assess(c(source_authorized=False, width_px=None),
                        Criteria(resolution=Resolution.P1440))
        self.assertEqual(result.verdict, Verdict.REJECT)
        self.assertIn("VIDEO_DIMENSIONS_UNVERIFIED", result.reasons)

    def test_multiple_distinct_seed_families_stay_separate(self):
        x = c(observations=(
            SeedObservation(SeedKind.REPORTED, 400, "site", "2026-11-05T10:00:00Z"),
            SeedObservation(SeedKind.CONNECTED, 2, "client", "2026-11-05T10:00:00Z"),
        ))
        self.assertEqual(assess(x, Criteria(min_seeds=300, seed_kind=SeedKind.REPORTED)).verdict,
                         Verdict.ELIGIBLE_METADATA)
        self.assertEqual(assess(x, Criteria(min_seeds=300, seed_kind=SeedKind.CONNECTED)).verdict,
                         Verdict.REJECT)


if __name__ == "__main__":
    unittest.main()
