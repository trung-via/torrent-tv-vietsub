"""Owner-provided release-group and resolution heuristics (no moviehash required)."""
import unittest

from matcher import Media, SearchResults, Subtitle, choose


class HeuristicTests(unittest.TestCase):
    def setUp(self):
        self.media = Media(
            "private-server", "torrent-identity-placeholder", 0,
            "Example.Film.2017.1080p.BluRay.x265-GRP.mkv",
            movie_hash=None)

    def decide(self, *subs):
        return choose(self.media, SearchResults(self.media.key, tuple(subs)))

    def test_group_and_bluray_year_confident_without_moviehash(self):
        d = self.decide(Subtitle("1", "Example.Film.2017.1080p.BluRay.x264-GRP.srt", "en"))
        self.assertEqual(d.status, "EN_TRANSLATE")
        self.assertTrue(d.winner.confident)
        self.assertIn("group", d.winner.evidence)
        self.assertIn("resolution", d.winner.evidence)

    def test_1080p_and_codec_without_group_stay_review_only(self):
        d = self.decide(Subtitle("1", "Example.Film.2017.1080p.BluRay.x265.srt", "en"))
        self.assertEqual(d.status, "REVIEW_REQUIRED")
        self.assertFalse(d.ranked[0].confident)
        self.assertIn("resolution", d.ranked[0].evidence)
        self.assertNotIn("group", d.ranked[0].evidence)

    def test_group_match_outranks_1080p_other_group(self):
        d = self.decide(
            Subtitle("1", "Example.Film.2017.1080p.BluRay.x265-OTHER.srt", "en"),
            Subtitle("2", "Example.Film.2017.720p.BluRay.x264-GRP.srt", "en"),
        )
        self.assertEqual(d.status, "EN_TRANSLATE")
        self.assertEqual(d.winner.subtitle_id, "2")
        self.assertGreater(d.ranked[0].score, d.ranked[1].score)

    def test_wrong_year_cannot_be_saved_by_group_or_resolution(self):
        d = self.decide(Subtitle("1", "Example.Film.2018.1080p.BluRay.x265-GRP.srt", "en"))
        self.assertEqual(d.status, "NO_MATCH")


if __name__ == "__main__":
    unittest.main()
