"""Pinned OMP Torznab SourceResult contract and safe conversion tests."""
import unittest
from candidate_verifier import Criteria, Resolution, Verdict
from omp_torznab_bridge import ApprovedOrigin, assess_omp_results, candidate_from_omp_result

TIME = "2026-11-05T15:00:00Z"
ORIGIN = ApprovedOrigin("ts-torznab", "allowed-test-tracker", True)


def row(**kw):
    x = {"source": "ts-torznab", "Tracker": "allowed-test-tracker",
         "Title": "TEST_1440p_VI_unverified", "Size": "10 GB",
         "sizeBytes": 10_000_000_000, "Seed": 350,
         "Hash": "a" * 40, "CreateDate": "2020-01-01",
         "Magnet": "magnet:?tr=private-passkey",
         "Link": "https://example.invalid/?secret=private-passkey"}
    x.update(kw)
    return x


def verdict(value, query=Criteria(), grant=ORIGIN):
    return assess_omp_results([value], grant, TIME, query)[0]


class OmpContractTests(unittest.TestCase):
    def test_exact_omp_fields(self):
        c = candidate_from_omp_result(row(), ORIGIN, TIME)
        self.assertEqual(c.file_size_bytes, 10_000_000_000)
        self.assertEqual(c.observations[0].count, 350)
        self.assertEqual(c.observations[0].observed_at, TIME)
        self.assertEqual(c.audio_languages, ())
        self.assertIsNone(c.width_px)

    def test_known_size_and_reported_seed_can_qualify(self):
        self.assertEqual(verdict(row(), Criteria(min_bytes=8_000_000_000,
                         max_bytes=12_000_000_000, min_seeds=300)).verdict,
                         Verdict.ELIGIBLE_METADATA)

    def test_unverified_resolution_and_language_do_not_pass(self):
        r = verdict(row(), Criteria(resolution=Resolution.P1440, require_audio_vi=True))
        self.assertEqual(r.verdict, Verdict.UNKNOWN)
        self.assertIn("VIDEO_DIMENSIONS_UNVERIFIED", r.reasons)
        self.assertIn("AUDIO_TRACK_METADATA_UNVERIFIED", r.reasons)

    def test_denied_grant(self):
        self.assertEqual(verdict(row(), grant=ApprovedOrigin("ts-torznab",
                         "allowed-test-tracker", False)).verdict, Verdict.REJECT)

    def test_row_source_and_tracker_mismatch(self):
        self.assertEqual(verdict(row(source="ts-rutor")).verdict, Verdict.REJECT)
        self.assertEqual(verdict(row(Tracker="different")).verdict, Verdict.REJECT)

    def test_merged_sources_do_not_bypass_primary(self):
        self.assertEqual(verdict(row(source="unknown",
                         sources=["ts-torznab"])).verdict, Verdict.REJECT)

    def test_reported_zero_and_missing_distinct(self):
        q = Criteria(min_seeds=300)
        self.assertEqual(verdict(row(Seed=0), q).verdict, Verdict.REJECT)
        self.assertEqual(verdict(row(Seed=None), q).verdict, Verdict.UNKNOWN)

    def test_malformed_seed_unknown(self):
        q = Criteria(min_seeds=300)
        for bad in (-1, True, "350", 350.0):
            with self.subTest(value=bad):
                self.assertEqual(verdict(row(Seed=bad), q).verdict, Verdict.UNKNOWN)

    def test_size_uses_sizeBytes_not_unverified_size_text(self):
        q = Criteria(min_bytes=8_000_000_000)
        for bad in (None, 0, True, "10000000000"):
            with self.subTest(value=bad):
                self.assertEqual(verdict(row(sizeBytes=bad), q).verdict, Verdict.UNKNOWN)

    def test_release_date_not_observation_date(self):
        c = candidate_from_omp_result(row(), ORIGIN, TIME)
        self.assertEqual(c.observations[0].observed_at, TIME)

    def test_secrets_not_in_output(self):
        result = repr(verdict(row()))
        for secret in ("private-passkey", "magnet:", "https://", "TEST_1440p"):
            self.assertNotIn(secret, result)

    def test_wrong_adapter_not_supported(self):
        with self.assertRaises(ValueError):
            ApprovedOrigin("ts-rutor", "allowed-test-tracker", True)

    def test_unzoned_capture_time_rejected(self):
        with self.assertRaises(ValueError):
            candidate_from_omp_result(row(), ORIGIN, "2026-11-05T15:00:00")

    def test_batch_limit(self):
        with self.assertRaises(ValueError):
            assess_omp_results([row()] * 101, ORIGIN, TIME, Criteria())


if __name__ == "__main__":
    unittest.main()
