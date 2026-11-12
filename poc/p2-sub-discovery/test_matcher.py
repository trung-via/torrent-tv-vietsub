"""Synthetic-only unit tests: no network, media content, tokens or download."""
import unittest

from matcher import Media, SearchResults, Subtitle, choose, parse_release


def film(movie_hash=None, file_index=0):
    return Media("home-profile", "synthetic-torrent-id", file_index, "Sample.Film.2017.1080p.BluRay.x265-TEAM.mkv", movie_hash)


def batch(media, *subtitles):
    return SearchResults(media.key, tuple(subtitles))


class MatcherTests(unittest.TestCase):
    def test_parse_release(self):
        r = parse_release(r"X:\Videos\Sample.Film.2017.1080p.BluRay.x265-TEAM.mkv")
        self.assertEqual((r.title, r.year, r.resolution, r.source, r.codec, r.group),
                         ("sample film", 2017, "1080p", "bluray", "x265", "team"))

    def test_same_release_vi_wins(self):
        media = film()
        vi = Subtitle("vi1", "Sample.Film.2017.1080p.BluRay.x265-TEAM.srt", "vi")
        en = Subtitle("en1", "Sample.Film.2017.1080p.BluRay.x265-TEAM.srt", "en")
        self.assertEqual(choose(media, batch(media, en, vi)).winner.subtitle_id, "vi1")

    def test_wrong_title_and_year_rejected_even_with_hash(self):
        media = film("0102030405060708")
        subs = [Subtitle("a", "Other.Film.2017.1080p.BluRay.x265-TEAM.srt", "vi", movie_hash="0102030405060708"),
                Subtitle("b", "Sample.Film.2018.1080p.BluRay.x265-TEAM.srt", "vi", movie_hash="0102030405060708")]
        self.assertEqual(choose(media, batch(media, *subs)).status, "NO_MATCH")

    def test_hash_beats_release(self):
        media = film("0102030405060708")
        exact = Subtitle("hash", "Sample.Film.2017.720p.WEB-DL.x264-OTHER.srt", "vi", movie_hash="0102030405060708")
        group = Subtitle("group", "Sample.Film.2017.1080p.BluRay.x265-TEAM.srt", "vi")
        self.assertEqual(choose(media, batch(media, group, exact)).winner.subtitle_id, "hash")

    def test_hash_conflict_disables_auto_selection(self):
        media = film("0102030405060708")
        sub = Subtitle("same-group-wrong-hash", "Sample.Film.2017.1080p.BluRay.x265-TEAM.srt", "vi", movie_hash="aaaaaaaaaaaaaaaa")
        self.assertEqual(choose(media, batch(media, sub)).status, "REVIEW_REQUIRED")

    def test_1080p_only_not_confident(self):
        media = film()
        sub = Subtitle("weak", "Sample.Film.2017.1080p.WEB-DL.x264-OTHER.srt", "vi")
        self.assertEqual(choose(media, batch(media, sub)).status, "REVIEW_REQUIRED")

    def test_english_fallback_only_when_confident(self):
        media = film()
        vi = Subtitle("viweak", "Sample.Film.2017.1080p.WEB-DL.x264-OTHER.srt", "vi")
        en = Subtitle("enstrong", "Sample.Film.2017.1080p.BluRay.x265-TEAM.srt", "en")
        self.assertEqual(choose(media, batch(media, vi, en)).status, "EN_TRANSLATE")

    def test_ambiguous_same_release_requires_review(self):
        media = film()
        a = Subtitle("a", "Sample.Film.2017.1080p.BluRay.x265-TEAM.srt", "vi")
        b = Subtitle("b", "Sample.Film.2017.1080p.BluRay.x265-TEAM.srt", "vi")
        self.assertEqual(choose(media, batch(media, a, b)).status, "REVIEW_REQUIRED")

    def test_file_binding(self):
        media = film(file_index=2)
        other = film(file_index=3)
        with self.assertRaisesRegex(ValueError, "media binding mismatch"):
            choose(media, batch(other, Subtitle("x", "Sample.Film.2017.1080p.BluRay.x265-TEAM.srt", "vi")))

    def test_duplicate_and_malformed_hash_rejected(self):
        media = film()
        sub = Subtitle("x", "Sample.Film.2017.1080p.BluRay.x265-TEAM.srt", "vi")
        with self.assertRaises(ValueError):
            choose(media, batch(media, sub, sub))
        with self.assertRaises(ValueError):
            film(movie_hash="not-a-hash")

    def test_unsupported_caption_and_empty_results(self):
        media = film()
        self.assertEqual(choose(media, batch(media, Subtitle("x", "Sample.Film.2017.1080p.BluRay.x265-TEAM.ass", "vi", fmt="ass"))).status, "NO_MATCH")
        self.assertEqual(choose(media, batch(media)).status, "NO_MATCH")


if __name__ == "__main__":
    unittest.main()
