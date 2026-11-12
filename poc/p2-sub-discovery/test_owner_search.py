"""Offline contract tests for VI→EN owner search; no real network/media."""
from urllib.parse import parse_qs, urlsplit
import unittest

from matcher import Media
from opensubtitles import OpenSubtitles, SubtitleApiError
from owner_search import search_status


NAME = "Sample.Film.2017.1080p.BluRay.x265-TEAM.mkv"


def api_rows(*items):
    import json
    return json.dumps({"data": list(items)}, separators=(",", ":")).encode("utf-8")


def api_row(file_id, *, lang, release):
    return {
        "attributes": {
            "language": lang,
            "release": release,
            "files": [{"file_id": file_id, "file_name": "sample.srt"}],
        }
    }


CONFIDENT = "Sample.Film.2017.1080p.BluRay.x265-TEAM"
WEAK = "Sample.Film.2017.1080p.WEB-DL.x264-OTHER"


class Stub:
    def __init__(self, table):
        self.table = table
        self.calls = []

    def __call__(self, method, url, headers, body, cap):
        assert method == "GET" and body is None, "Search probe must never download"
        query = parse_qs(urlsplit(url).query)
        code = query["languages"][0]
        mode = "release" if "TEAM" in query["query"][0] else "title"
        self.calls.append((method, code, mode, headers["Api-Key"]))
        return self.table.get((code, mode), api_rows())


def cli(table, name=NAME):
    spy = Stub(table)
    client = OpenSubtitles(api_key="test-private", transport=spy)
    return search_status(client, name), spy.calls


class OwnerSearchTests(unittest.TestCase):
    def test_vi_release_match_short_circuits(self):
        lines, calls = cli({("vi", "release"): api_rows(api_row(7, lang="vi", release=CONFIDENT))})
        self.assertEqual(lines[-2:], ("NEXT_GATE=VI_MATCH", "DOWNLOAD_REQUESTS=0"))
        self.assertIn("BEST_MATCH_EVIDENCE=title,year,source,group,resolution,codec", lines)
        self.assertEqual([(x[1], x[2]) for x in calls], [("vi", "release")])

    def test_fallback_title_search_if_release_not_found(self):
        lines, calls = cli({("vi", "title"): api_rows(api_row(8, lang="vi", release=CONFIDENT))})
        self.assertIn("VI_TITLE_DECISION=VI_MATCH", lines)
        self.assertEqual(len(calls), 2)
        self.assertEqual(lines[-1], "DOWNLOAD_REQUESTS=0")

    def test_search_en_only_if_vi_lacks_confident_match(self):
        lines, calls = cli({("vi", "release"): api_rows(api_row(9, lang="vi", release=WEAK)),
                            ("en", "release"): api_rows(api_row(10, lang="en", release=CONFIDENT))})
        self.assertIn("VI_RELEASE_DECISION=REVIEW_REQUIRED", lines)
        self.assertIn("NEXT_GATE=EN_TRANSLATE", lines)
        self.assertEqual([(x[1], x[2]) for x in calls],
                         [("vi", "release"), ("vi", "title"), ("en", "release")])

    def test_empty_response_never_requests_download(self):
        lines, calls = cli({})
        self.assertIn("NEXT_GATE=NO_MATCH", lines)
        self.assertEqual(len(calls), 4)
        self.assertTrue(all(x[0] == "GET" for x in calls))

    def test_vi_weak_requiring_review(self):
        lines, calls = cli({("vi", "release"): api_rows(api_row(11, lang="vi", release=WEAK))})
        self.assertIn("NEXT_GATE=REVIEW_REQUIRED", lines)
        self.assertEqual(len(calls), 4)

    def test_no_secret_or_release_name_appears_in_result(self):
        lines, _ = cli({("vi", "release"): api_rows(api_row(7, lang="vi", release=CONFIDENT))})
        output = "\n".join(lines)
        self.assertNotIn("test-private", output)
        self.assertNotIn("Sample.Film", output)
        self.assertNotIn("not-a-real-torrserver-hash", output)

    def test_path_or_control_char_rejected_before_network(self):
        for name in ("../Sample.Film.2017.mkv", "C:\\Media\\sample.mkv",
                     "name\ninjected", "", " "):
            with self.subTest(name=name):
                with self.assertRaisesRegex(SubtitleApiError, "BAD_MEDIA_FILENAME"):
                    cli({}, name)

    def test_provider_auth_failure_is_not_swallowed(self):
        class AuthFailure:
            def search(self, media, *, language, query_mode):
                raise SubtitleApiError("API_AUTH_DENIED")
        with self.assertRaisesRegex(SubtitleApiError, "API_AUTH_DENIED"):
            search_status(AuthFailure(), NAME)

    def test_bad_query_mode_rejected_before_network(self):
        class Explode:
            def __call__(self, *args):
                raise AssertionError("Unexpected network")
        client = OpenSubtitles(api_key="key", transport=Explode())
        m = Media("owner", "torrent", 0, NAME)
        with self.assertRaisesRegex(SubtitleApiError, "UNSUPPORTED_QUERY_MODE"):
            client.search(m, language="vi", query_mode="unknown")


if __name__ == "__main__":
    unittest.main()
