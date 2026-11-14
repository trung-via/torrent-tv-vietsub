"""Offline contract tests for VI→EN owner search; no real network/media."""
from urllib.parse import parse_qs, urlsplit
import unittest

from matcher import Media
from opensubtitles import OpenSubtitles, SubtitleApiError
from owner_search import search_status, diagnostic_status, review_status


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
        mode = "imdb" if "imdb_id" in query else ("release" if "TEAM" in query["query"][0] else "title")
        self.calls.append((method, code, mode, headers["Api-Key"]))
        return self.table.get((code, mode), api_rows())


def cli(table, name=NAME, imdb_id=None):
    spy = Stub(table)
    client = OpenSubtitles(api_key="test-private", transport=spy)
    return search_status(client, name, imdb_id=imdb_id), spy.calls


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
            def search(self, media, *, language, query_mode, imdb_id=None):
                raise SubtitleApiError("API_AUTH_DENIED")
        with self.assertRaisesRegex(SubtitleApiError, "API_AUTH_DENIED"):
            search_status(AuthFailure(), NAME)

    def test_api_zero_is_distinct_from_parser_rejection(self):
        lines, _ = cli({})
        self.assertIn("VI_TITLE_RAW_ROWS=0", lines)
        self.assertIn("DIAGNOSTIC=API_RETURNED_ZERO_RAW_ROWS", lines)
        # API may contain rows which the app discarded; do not mislabel them
        # as OpenSubtitles having no data for the film.
        lines, _ = cli({("vi", "title"): api_rows({"attributes": {"language": "vi", "files": []}})})
        self.assertIn("VI_TITLE_RAW_ROWS=1", lines)
        self.assertIn("VI_TITLE_CANDIDATES=0", lines)
        self.assertIn("DIAGNOSTIC=API_HAS_ROWS_BUT_NO_RANKABLE_MATCH", lines)

    def test_imdb_fallback_uses_id_without_year_or_title(self):
        lines, calls = cli({("vi", "imdb"): api_rows(api_row(19, lang="vi", release=CONFIDENT))},
                           imdb_id="3501632")
        self.assertIn("VI_IMDB_DECISION=VI_MATCH", lines)
        self.assertIn("VI_IMDB_RAW_ROWS=1", lines)
        self.assertEqual([x[2] for x in calls], ["release", "title", "imdb"])
        self.assertTrue(all(x[0] == "GET" for x in calls))
        self.assertIn("DOWNLOAD_REQUESTS=0", lines)

    def test_imdb_id_is_validated_before_network(self):
        class Explode:
            def __call__(self, *args):
                raise AssertionError("Unexpected network")
        client = OpenSubtitles(api_key="key", transport=Explode())
        m = Media("owner", "torrent", 0, NAME)
        for invalid in ("Thor", "tt", "../1", "x3501632", "", "1" * 13):
            with self.subTest(imdb=invalid):
                with self.assertRaisesRegex(SubtitleApiError, "INVALID_IMDB_ID"):
                    client.search(m, language="vi", query_mode="imdb", imdb_id=invalid)

    def test_api_total_diagnostic_without_private_text(self):
        import json
        response = json.dumps({"total_count": 51, "data": [
            {"attributes": {"language": "vi", "release": WEAK,
                            "files": [{"file_id": 7, "file_name": "sample.srt"}]}}
        ]}).encode()
        lines, _ = cli({("vi", "title"): response})
        self.assertIn("VI_TITLE_API_TOTAL=51", lines)
        self.assertIn("VI_TITLE_RAW_ROWS=1", lines)
        self.assertNotIn("sample.srt", "\\n".join(lines))
        self.assertIn("DOWNLOAD_REQUESTS=0", lines)

    def test_targeted_imdb_schema_diagnostic_exactly_two_gets(self):
        import json
        only_rows = json.dumps({"total_count": 6, "data": [
            {"attributes": {"language": "vi", "release": "Private Synthetic Title",
                            "files": [{"file_id": 11, "file_name": "subtitle.ass"}]}}
        ]}).encode()
        spy = Stub({("vi", "imdb"): only_rows,
                    ("en", "imdb"): api_rows(api_row(12, lang="en", release=CONFIDENT))})
        client = OpenSubtitles(api_key="very-secret", transport=spy)
        lines = diagnostic_status(client, NAME, imdb_id="3501632")
        self.assertEqual([(x[0], x[1], x[2]) for x in spy.calls],
                         [("GET", "vi", "imdb"), ("GET", "en", "imdb")])
        self.assertIn("VI_IMDB_RAW_ROWS=1", lines)
        self.assertIn("VI_IMDB_CANDIDATES=1", lines)
        self.assertIn("VI_IMDB_RANKED=0", lines)  # Provider metadata without title match
        self.assertNotIn("VI_IMDB_REJECT_UNSUPPORTED_EXTENSION=1", lines)
        self.assertIn("EN_IMDB_CANDIDATES=1", lines)
        self.assertIn("EN_IMDB_CONFIDENT=1", lines)
        self.assertIn("EN_IMDB_GROUP_MATCHES=1", lines)
        self.assertIn("VI_IMDB_CONFIDENT=0", lines)
        self.assertIn("VI_IMDB_GROUP_MATCHES=0", lines)
        self.assertIn("DOWNLOAD_REQUESTS=0", lines)
        self.assertNotIn("very-secret", "\\n".join(lines))
        self.assertNotIn("Private Synthetic Title", "\\n".join(lines))

    def test_schema_diagnostic_empty_api_vs_missing_files(self):
        spy = Stub({("vi", "imdb"): api_rows({"attributes": {
            "language": "vi", "files": []}})})
        client = OpenSubtitles(api_key="key", transport=spy)
        lines = diagnostic_status(client, NAME, imdb_id="3501632")
        self.assertIn("VI_IMDB_REJECT_MISSING_FILES=1", lines)
        self.assertIn("VI_IMDB_RAW_ROWS=1", lines)
        self.assertIn("EN_IMDB_RAW_ROWS=0", lines)
        self.assertEqual(len(spy.calls), 2)

    def test_owner_review_bounded_page2_gets_and_release_hints(self):
        import json

        class PageTransport:
            def __init__(self):
                self.calls = []

            def __call__(self, method, url, headers, body, cap):
                query = parse_qs(urlsplit(url).query)
                self.calls.append((method, query, headers, body))
                self_test.assertEqual(method, "GET")
                self_test.assertIsNone(body)
                language = query["languages"][0]
                page = int(query.get("page", ["1"])[0])
                if language == "vi":
                    self_test.assertEqual(page, 1)
                    return json.dumps({"total_count": 1, "data": [
                        api_row(60, lang="vi", release=WEAK),
                    ]}).encode()
                if page == 1:
                    data = [api_row(i, lang="en", release=WEAK) for i in range(1, 51)]
                    return json.dumps({"total_count": 58, "data": data}).encode()
                self_test.assertEqual(page, 2)
                data = [api_row(100, lang="en", release=CONFIDENT)]
                data.extend(api_row(i, lang="en", release=WEAK) for i in range(101, 108))
                return json.dumps({"total_count": 58, "data": data}).encode()

        self_test = self
        spy = PageTransport()
        client = OpenSubtitles(api_key="private", transport=spy)
        lines = review_status(client, NAME, imdb_id="3501632")
        self.assertIn("D2_RELEASE_REVIEW", lines)
        self.assertIn("EN_PAGE1_RAW_ROWS=50", lines)
        self.assertIn("EN_PAGE2_RAW_ROWS=8", lines)
        self.assertIn("EN_RETRIEVED_ROWS=58", lines)
        self.assertIn("EN_COVERAGE=FIRST_PAGE_OR_COMPLETE", lines)
        self.assertIn("EN_GROUP_MATCHES=1", lines)
        self.assertIn("EN_TOP1_GROUP=YES", lines)
        self.assertIn("EN_TOP1_SOURCE=YES", lines)
        self.assertIn("VI_GROUP_MATCHES=0", lines)
        self.assertIn("SEARCH_REQUESTS=3", lines)
        self.assertIn("DOWNLOAD_REQUESTS=0", lines)
        self.assertIn("AUTO_DOWNLOAD_ALLOWED=NO", lines)
        output = "\n".join(lines)
        self.assertNotIn("private", output)
        self.assertNotIn("Sample.Film", output)
        self.assertNotIn("100", "\n".join(x for x in lines if "_TOP" in x and "_SCORE=" not in x))
        self.assertEqual([x[0] for x in spy.calls], ["GET", "GET", "GET"])

    def test_owner_review_no_extra_page_on_short_result(self):
        spy = Stub({("vi", "imdb"): api_rows(api_row(7, lang="vi", release=WEAK)),
                    ("en", "imdb"): api_rows(api_row(8, lang="en", release=WEAK))})
        result = review_status(OpenSubtitles(api_key="fake", transport=spy),
                               NAME, imdb_id="3501632")
        self.assertIn("SEARCH_REQUESTS=2", result)
        self.assertIn("DOWNLOAD_REQUESTS=0", result)
        self.assertNotIn("EN_PAGE2_RAW_ROWS=0", result)

    def test_owner_review_refuses_bad_filename(self):
        class NoNetwork:
            def search(self, *args, **kwargs):
                raise AssertionError("network should not run")

        for value in ("", "../bad", "C:\\media\\bad", "a\nb", " "):
            with self.subTest(value=value):
                with self.assertRaisesRegex(SubtitleApiError, "BAD_MEDIA_FILENAME"):
                    review_status(NoNetwork(), value, imdb_id="3501632")

    def test_bounded_second_page_input(self):
        class NoNetwork:
            def __call__(self, *args):
                raise AssertionError("network should not run")

        cli = OpenSubtitles(api_key="fake", transport=NoNetwork())
        m = Media("profile", "hash", 0, NAME)
        for page in (0, -1, 3, True, "2"):
            with self.subTest(page=page):
                with self.assertRaisesRegex(SubtitleApiError, "UNSUPPORTED_PAGE"):
                    cli.search(m, language="en", query_mode="imdb",
                               imdb_id="3501632", page=page)

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
