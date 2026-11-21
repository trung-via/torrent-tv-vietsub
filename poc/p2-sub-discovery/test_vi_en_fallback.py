"""Offline unit tests for VI-first, EN-fallback routing; zero downloads."""
import json
import unittest
from urllib.parse import parse_qs, urlsplit

from matcher import Media
from opensubtitles import OpenSubtitles, SubtitleApiError
from vi_en_fallback import select_vi_then_en

FILM = "Example.Film.2017.1080p.BluRay.x265-GROUP.mkv"
SAME = "Example.Film.2017.1080p.BluRay.x265-GROUP"
WEAK = "Example.Film.2017.1080p.BluRay.x264-OTHER"


def make_row(file_id, release, language):
    return {"attributes": {"language": language, "release": release,
                            "files": [{"file_id": file_id, "file_name": "unverified.ass"}]}}


class Fake:
    def __init__(self, table):
        self.table, self.calls = table, []

    def __call__(self, method, url, headers, body, cap):
        q = parse_qs(urlsplit(url).query)
        lang, page = q["languages"][0], int(q.get("page", ["1"])[0])
        self.calls.append((method, lang, page))
        if method != "GET" or body is not None:
            raise AssertionError("Only metadata GET permitted")
        rows, total = self.table.get((lang, page), ([], 0))
        return json.dumps({"data": rows, "total_count": total}).encode("utf-8")


def run(table, *, policy="VI_FAST"):
    fake = Fake(table)
    route = select_vi_then_en(OpenSubtitles(api_key="PRIVATE_TOKEN", transport=fake),
                              Media("profile", "hash", 0, FILM),
                              imdb_id="3501632", policy=policy)
    return route, fake.calls


class RouteTests(unittest.TestCase):
    def test_confident_vi_stops_before_en(self):
        route, calls = run({("vi", 1): ([make_row(7, SAME, "vi")], 1)})
        self.assertEqual(route.status, "VI_READY")
        self.assertEqual(route.selected_file_id, 7)
        self.assertEqual(route.language, "vi")
        self.assertEqual(route.get_requests, 1)
        self.assertEqual(calls, [("GET", "vi", 1)])
        self.assertFalse(route.video_sync_verified)

    def test_unmatched_vi_falls_back_to_confident_en(self):
        route, calls = run({
            ("vi", 1): ([make_row(9, WEAK, "vi")], 1),
            ("en", 1): ([make_row(5, SAME, "en")], 1),
        })
        self.assertEqual(route.status, "EN_TRANSLATE")
        self.assertEqual(route.selected_file_id, 5)
        self.assertEqual(route.vi.decision.status, "REVIEW_REQUIRED")
        self.assertEqual(route.language, "en")
        self.assertEqual(calls, [("GET", "vi", 1), ("GET", "en", 1)])

    def test_en_page_two_is_searched_before_route(self):
        rows = [make_row(i, WEAK, "en") for i in range(1, 51)]
        route, calls = run({
            ("en", 1): (rows, 51),
            ("en", 2): ([make_row(70, SAME, "en")], 51),
        })
        self.assertEqual(route.status, "EN_TRANSLATE")
        self.assertEqual(route.selected_file_id, 70)
        self.assertEqual(route.en.raw_rows, 51)
        self.assertEqual(route.get_requests, 3)
        self.assertEqual(calls[-1], ("GET", "en", 2))

    def test_ambiguous_en_requires_review(self):
        route, calls = run({("en", 1): ([
            make_row(10, SAME, "en"), make_row(11, SAME, "en")], 2)})
        self.assertEqual(route.status, "REVIEW_REQUIRED")
        self.assertIsNone(route.selected_file_id)
        self.assertEqual(route.get_requests, 2)

    def test_no_match(self):
        route, calls = run({})
        self.assertEqual(route.status, "NO_MATCH")
        self.assertIsNone(route.language)
        self.assertEqual(route.get_requests, 2)

    def test_partial_vi_blocks_en_preemption(self):
        first = [make_row(i, WEAK, "vi") for i in range(1, 51)]
        route, calls = run({
            ("vi", 1): (first, 110),
            ("vi", 2): ([make_row(60, SAME, "vi")], 110),
            ("en", 1): ([make_row(80, SAME, "en")], 1),
        }, policy="VI_FULL")
        self.assertEqual(route.status, "REVIEW_REQUIRED")
        self.assertEqual(route.reason, "VI_COVERAGE_INCOMPLETE")
        self.assertNotIn(("GET", "en", 1), calls)

    def test_vi_fast_one_get_then_en_on_incomplete_vi(self):
        vi_rows = [make_row(i, WEAK, "vi") for i in range(1, 51)]
        route, calls = run({
            ("vi", 1): (vi_rows, 110),
            ("vi", 2): ([make_row(60, SAME, "vi")], 110),
            ("en", 1): ([make_row(90, SAME, "en")], 1),
        })
        self.assertEqual(route.status, "EN_TRANSLATE")
        self.assertEqual(route.search_policy, "VI_FAST")
        self.assertEqual(route.vi_probe_status, "INCOMPLETE")
        self.assertEqual(calls, [("GET", "vi", 1), ("GET", "en", 1)])
        self.assertEqual(route.get_requests, 2)

    def test_fast_does_not_promote_vi_winner_from_partial_page(self):
        vi_rows = [make_row(i, WEAK, "vi") for i in range(1, 50)]
        vi_rows.append(make_row(99, SAME, "vi"))
        route, calls = run({
            ("vi", 1): (vi_rows, 60),
            ("en", 1): ([make_row(90, SAME, "en")], 1)
        })
        self.assertEqual(route.status, "EN_TRANSLATE")
        self.assertEqual(route.language, "en")
        self.assertEqual(route.vi_probe_status, "INCOMPLETE")

    def test_en_direct_skips_vi_network_entirely(self):
        route, calls = run({
            ("vi", 1): ([make_row(5, SAME, "vi")], 1),
            ("en", 1): ([make_row(6, SAME, "en")], 1),
        }, policy="EN_DIRECT")
        self.assertEqual(route.status, "EN_TRANSLATE")
        self.assertEqual(route.search_policy, "EN_DIRECT")
        self.assertEqual(route.vi_probe_status, "SKIPPED")
        self.assertEqual(route.vi.raw_rows, 0)
        self.assertEqual(route.get_requests, 1)
        self.assertEqual(calls, [("GET", "en", 1)])

    def test_vi_full_page2_can_take_priority_over_en(self):
        vi_rows = [make_row(i, WEAK, "vi") for i in range(1, 51)]
        route, calls = run({
            ("vi", 1): (vi_rows, 51),
            ("vi", 2): ([make_row(99, SAME, "vi")], 51),
            ("en", 1): ([make_row(90, SAME, "en")], 1),
        }, policy="VI_FULL")
        self.assertEqual(route.status, "VI_READY")
        self.assertEqual(route.selected_file_id, 99)
        self.assertEqual(calls, [("GET", "vi", 1), ("GET", "vi", 2)])

    def test_transient_vi_network_failure_falls_back_en(self):
        class Flaky(Fake):
            def __call__(self, method, url, headers, body, cap):
                lang = parse_qs(urlsplit(url).query)["languages"][0]
                if lang == "vi":
                    self.calls.append((method, lang, 1))
                    raise SubtitleApiError("API_NETWORK_ERROR")
                return super().__call__(method, url, headers, body, cap)
        fake = Flaky({("en", 1): ([make_row(30, SAME, "en")], 1)})
        route = select_vi_then_en(
            OpenSubtitles(api_key="PRIVATE_TOKEN", transport=fake),
            Media("profile", "hash", 0, FILM), imdb_id="3501632")
        self.assertEqual(route.status, "EN_TRANSLATE")
        self.assertEqual(route.vi_probe_status, "NETWORK_ERROR_FALLBACK")
        self.assertEqual(route.get_requests, 2)
        self.assertEqual(fake.calls, [("GET", "vi", 1), ("GET", "en", 1)])

    def test_provider_auth_vi_failure_does_not_retry_en(self):
        class AuthBlocked:
            def __init__(self):
                self.count = 0
            def __call__(self, *args):
                self.count += 1
                raise SubtitleApiError("API_AUTH_DENIED")
        fake = AuthBlocked()
        with self.assertRaisesRegex(SubtitleApiError, "API_AUTH_DENIED"):
            select_vi_then_en(OpenSubtitles(api_key="PRIVATE_TOKEN", transport=fake),
                              Media("profile", "hash", 0, FILM), imdb_id="3501632")
        self.assertEqual(fake.count, 1)

    def test_unknown_policy_and_bad_timeout_fail_before_network(self):
        class RejectNetwork:
            def __call__(self, *args):
                raise AssertionError("network should not run")
        cli = OpenSubtitles(api_key="PRIVATE_TOKEN", transport=RejectNetwork())
        media = Media("profile", "hash", 0, FILM)
        with self.assertRaisesRegex(SubtitleApiError, "UNSUPPORTED_SEARCH_POLICY"):
            select_vi_then_en(cli, media, imdb_id="3501632", policy="UNKNOWN")
        for value in (0, -1, 16, True, "4"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(SubtitleApiError, "INVALID_SEARCH_TIMEOUT"):
                    select_vi_then_en(cli, media, imdb_id="3501632",
                                      vi_timeout_seconds=value)

    def test_duplicate_file_id_conflicting_metadata_fails_closed(self):
        first = [make_row(i, WEAK, "en") for i in range(1, 51)]
        second = make_row(1, SAME, "en")
        with self.assertRaisesRegex(SubtitleApiError, "CONFLICTING_PROVIDER_CANDIDATE"):
            run({("en", 1): (first, 51), ("en", 2): ([second], 51)})

    def test_partial_en_never_auto_downloadable(self):
        first = [make_row(i, WEAK, "en") for i in range(1, 50)]
        first.append(make_row(50, SAME, "en"))
        route, _ = run({("en", 1): (first, 110),
                        ("en", 2): ([make_row(51, WEAK, "en")], 110)})
        self.assertEqual(route.status, "REVIEW_REQUIRED")
        self.assertEqual(route.reason, "EN_COVERAGE_INCOMPLETE")

    def test_only_metadata_get_no_secrets_in_selection(self):
        route, calls = run({("en", 1): ([make_row(7, SAME, "en")], 1)})
        self.assertEqual(route.status, "EN_TRANSLATE")
        self.assertEqual([x[0] for x in calls], ["GET", "GET"])
        self.assertNotIn("PRIVATE_TOKEN", str(route))
        self.assertNotIn("https://", str(route))


if __name__ == "__main__":
    unittest.main()
