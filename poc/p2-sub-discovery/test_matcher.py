"""Synthetic-only unit tests: no network, media content, tokens or download."""
import unittest

from matcher import Media, SearchResults, Subtitle, choose, parse_release, preferred_media_release


def film(movie_hash=None, file_index=0):
    return Media("home-profile", "synthetic-torrent-id", file_index, "Sample.Film.2017.1080p.BluRay.x265-TEAM.mkv", movie_hash)


def batch(media, *subtitles):
    return SearchResults(media.key, tuple(subtitles))


class MatcherTests(unittest.TestCase):
    def test_cyrillic_filename_uses_international_torrent_alias(self):
        name = "Пример. (2017). BDRip-HEVC 1080p.x265.mkv"
        label = "Пример / Example Film (2017) BDRip-HEVC 1080p | P | Voice"
        self.assertEqual(parse_release(name).title, "пример")
        media = Media("home", "torrent", 4, name, torrent_title=label)
        selected = preferred_media_release(media)
        self.assertEqual((selected.title, selected.year, selected.source,
                          selected.resolution, selected.codec),
                         ("example film", 2017, "bluray", "1080p", "hevc"))
        winner = Subtitle("vi", "Example.Film.2017.1080p.BluRay.HEVC.vi.srt", "vi")
        self.assertEqual(choose(media, batch(media, winner)).status, "VI_MATCH")
        self.assertEqual(media.key, ("home", "torrent", 4))
        self.assertEqual(media.filename, name)

    def test_torrent_alias_must_not_override_conflicting_media_year(self):
        media = Media("home", "torrent", 0, "Пример.2017.BDRip.1080p.mkv",
                      torrent_title="Пример / Other Film (2018) BDRip 1080p")
        self.assertEqual(preferred_media_release(media).title, "пример")
        mismatch = Subtitle("vi", "Other.Film.2018.BDRip.1080p.srt", "vi")
        self.assertEqual(choose(media, batch(media, mismatch)).status, "NO_MATCH")

    def test_different_resolution_without_real_moviehash_needs_review(self):
        media = Media("home", "torrent", 0, "Example.Film.2017.1080p.BDRip.mkv")
        remux = Subtitle("vi", "Example.Film.2017.2160p.Blu-ray.srt", "vi")
        self.assertEqual(parse_release(remux.release_name).source, "bluray")
        self.assertEqual(choose(media, batch(media, remux)).status,
                         "REVIEW_REQUIRED")

    def test_parse_release(self):
        r = parse_release(r"X:\Videos\Sample.Film.2017.1080p.BluRay.x265-TEAM.mkv")
        self.assertEqual((r.title, r.year, r.resolution, r.source, r.codec, r.group),
                         ("sample film", 2017, "1080p", "bluray", "x265", "team"))

    def test_provider_language_and_sdh_suffix_do_not_hide_video_group(self):
        examples = (
            "Sample.Film.2017.1080p.BluRay.x265-TEAM_eng",
            "Sample.Film.2017.1080p.BluRay.x265-TEAM_eng SDH",
            "Sample.Film.2017.1080p.BluRay.x265-TEAM.eng.sdh.srt",
            "Sample.Film.2017.1080p.BluRay.x265-TEAM-English",
            "Sample.Film.2017.1080p.BluRay.x265-TEAM_eng.hearing_impaired",
        )
        for name in examples:
            with self.subTest(name=name):
                parsed = parse_release(name)
                self.assertEqual(parsed.group, "team")
                self.assertEqual(parsed.title, "sample film")
                self.assertEqual(parsed.year, 2017)
                self.assertEqual(parsed.source, "bluray")
                self.assertEqual(parsed.resolution, "1080p")
                self.assertEqual(parsed.codec, "x265")

    def test_true_group_mismatch_not_hidden_by_language_marker(self):
        other = parse_release("Sample.Film.2017.1080p.BluRay.x265-OTHER_eng.srt")
        self.assertEqual(other.group, "other")
        d = choose(film(), batch(film(), Subtitle(
            "en-other", "Sample.Film.2017.1080p.BluRay.x265-OTHER_eng", "en")))
        self.assertEqual(d.status, "REVIEW_REQUIRED")

    def test_non_sdh_selected_over_same_release_sdh_for_translation(self):
        media = film()
        plain = Subtitle("normal", "Sample.Film.2017.1080p.BluRay.x265-TEAM_eng", "en")
        sdh = Subtitle("sdh", "Sample.Film.2017.1080p.BluRay.x265-TEAM_eng SDH", "en")
        selected = choose(media, batch(media, sdh, plain))
        self.assertEqual(selected.status, "EN_TRANSLATE")
        self.assertEqual(selected.winner.subtitle_id, "normal")
        self.assertEqual([r.score for r in selected.ranked], [97, 87])
        self.assertTrue(all(r.confident for r in selected.ranked))
        self.assertTrue(all("group" in r.evidence for r in selected.ranked))
        self.assertIn("sdh_variant", selected.ranked[1].evidence)

    def test_sdh_only_eligible_but_duplicate_plain_still_review(self):
        media = film()
        sdh = Subtitle("sdh", "Sample.Film.2017.1080p.BluRay.x265-TEAM_eng SDH", "en")
        self.assertEqual(choose(media, batch(media, sdh)).status, "EN_TRANSLATE")
        a = Subtitle("a", "Sample.Film.2017.1080p.BluRay.x265-TEAM_eng", "en")
        b = Subtitle("b", "Sample.Film.2017.1080p.BluRay.x265-TEAM.english.srt", "en")
        self.assertEqual(choose(media, batch(media, a, b)).status, "REVIEW_REQUIRED")

    def test_no_false_release_group_for_web_dl(self):
        r = parse_release("Sample.Film.2017.1080p.WEB-DL.srt")
        self.assertEqual((r.title, r.year, r.source, r.group), ("sample film", 2017, "web", None))

    def test_unique_same_title_year_source_with_missing_group_and_codec(self):
        media = Media("home", "torrent", 0, "Sample.Film.2017.1080p.WEB-DL.mkv")
        match = Subtitle("en10", "Sample.Film.2017.1080p.WEB-DL_eng.srt", "en")
        selected = choose(media, batch(media, match))
        self.assertEqual(selected.status, "EN_TRANSLATE")
        self.assertEqual(selected.winner.subtitle_id, "en10")
        self.assertNotIn("group", selected.winner.evidence)
        self.assertNotIn("codec", selected.winner.evidence)

    def test_missing_group_does_not_override_known_source_conflict(self):
        media = Media("home", "torrent", 0, "Sample.Film.2017.1080p.WEB-DL.mkv")
        different = Subtitle("en20", "Sample.Film.2017.1080p.BluRay_eng.srt", "en")
        self.assertEqual(choose(media, batch(media, different)).status,
                         "REVIEW_REQUIRED")

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
