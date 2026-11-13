"""Synthetic GET-only smoke tests for the owner D2.5 VI_FAST real API probe."""
import json
import unittest
from urllib.parse import parse_qs, urlsplit

from opensubtitles import OpenSubtitles, SubtitleApiError
from owner_search_probe import search_only_status


FILM = "Example.Film.2017.1080p.BluRay.x265-GRP.mkv"
MATCHED = "Example.Film.2017.1080p.BluRay.x265-GRP"
WEAK = "Example.Film.2017.1080p.BluRay.x265"
ALTERNATE = "Example.Film.2017.1080p.BluRay.x264-OTHER"


def row(file_id, release, language):
    return {"attributes": {
        "language": language, "release": release,
        "files": [{"file_id": file_id, "file_name": "source.ass"}],
    }}


class GetOnly:
    def __init__(self, table):
        self.table = table
        self.calls = []
        self.urls = []

    def __call__(self, method, url, headers, body, cap):
        self.assert_get_only(method, body)
        q = parse_qs(urlsplit(url).query)
        lang, page = q["languages"][0], int(q.get("page", ["1"])[0])
        self.calls.append((method, lang, page))
        self.urls.append(q)
        rows, total = self.table.get((lang, page), ([], 0))
        return json.dumps({"data": rows, "total_count": total}).encode("utf-8")

    @staticmethod
    def assert_get_only(method, body):
        if method != "GET" or body is not None:
            raise AssertionError("POST, download or model API not authorized")


class SmokeTests(unittest.TestCase):
    def probe(self, table, policy="VI_FAST", imdb_id="3501632"):
        transport = GetOnly(table)
        client = OpenSubtitles(api_key="OWNER_SECRET_NEVER_PRINT", transport=transport)
        result = search_only_status(client, FILM, imdb_id, policy=policy)
        return result, transport.calls

    def test_fast_vi_one_get_and_en_page2_eight_rows(self):
        # Replica of the previous owner-facing 6-VI and 58-EN page counts.
        vi = [row(i, WEAK, "vi") for i in range(1, 7)]
        en1 = [row(i, ALTERNATE, "en") for i in range(10, 60)]
        en2 = [row(i, WEAK, "en") for i in range(60, 68)]
        output, calls = self.probe({
            ("vi", 1): (vi, 6),
            ("en", 1): (en1, 58),
            ("en", 2): (en2, 58),
        })
        self.assertEqual(calls, [("GET", "vi", 1), ("GET", "en", 1),
                                 ("GET", "en", 2)])
        self.assertIn("SEARCH_POLICY=VI_FAST", output)
        self.assertIn("VI_RAW_ROWS=6", output)
        self.assertIn("EN_RAW_ROWS=58", output)
        self.assertIn("SEARCH_GET_REQUESTS=3", output)
        self.assertIn("DOWNLOAD_POST_REQUESTS=0", output)
        self.assertIn("ROUTE=REVIEW_REQUIRED", output)
        self.assertIn("VIDEO_RELEASE_GROUP=grp", output)
        text = "\n".join(output)
        self.assertNotIn("OWNER_SECRET_NEVER_PRINT", text)
        self.assertNotIn("file_id", text)
        self.assertNotIn("source.ass", text)

    def test_vi_confident_stops_after_one_get(self):
        out, calls = self.probe({
            ("vi", 1): ([row(5, MATCHED, "vi")], 1),
            ("en", 1): ([row(7, MATCHED, "en")], 1),
        })
        self.assertEqual(calls, [("GET", "vi", 1)])
        self.assertIn("ROUTE=VI_READY", out)
        self.assertIn("VI_GROUP_MATCHES=1", out)
        self.assertIn("EN_SEARCHED=NO", out)

    def test_en_direct_never_fetches_vi(self):
        out, calls = self.probe({
            ("vi", 1): ([row(5, MATCHED, "vi")], 1),
            ("en", 1): ([row(7, MATCHED, "en")], 1),
        }, policy="EN_DIRECT")
        self.assertEqual(calls, [("GET", "en", 1)])
        self.assertIn("VI_SEARCHED=NO", out)
        self.assertIn("ROUTE=EN_TRANSLATE", out)
        self.assertIn("DOWNLOAD_POST_REQUESTS=0", out)

    def test_title_year_search_from_filename_without_imdb_id(self):
        transport = GetOnly({
            ("vi", 1): ([row(5, WEAK, "vi")], 1),
            ("en", 1): ([row(6, MATCHED, "en")], 1),
        })
        client = OpenSubtitles(api_key="LOCAL", transport=transport)
        status = search_only_status(client, FILM, policy="VI_FAST")
        self.assertIn("QUERY_MODE=PARSED_TITLE_YEAR", status)
        self.assertIn("PARSED_TITLE=Example Film", status)
        self.assertIn("PARSED_YEAR=2017", status)
        self.assertIn("PARSED_SOURCE=bluray", status)
        self.assertIn("PARSED_CODEC=x265", status)
        self.assertIn("VIDEO_RELEASE_GROUP=grp", status)
        self.assertIn("VIDEO_RESOLUTION=1080p", status)
        self.assertIn("ROUTE=EN_TRANSLATE", status)
        self.assertEqual(transport.calls, [("GET", "vi", 1), ("GET", "en", 1)])
        self.assertEqual([x["query"] for x in transport.urls],
                         [["example film"], ["example film"]])
        self.assertEqual([x["year"] for x in transport.urls],
                         [["2017"], ["2017"]])
        self.assertTrue(all("imdb_id" not in x for x in transport.urls))
        self.assertTrue(all("GRP" not in str(x) and "x265" not in str(x)
                            for x in transport.urls))
        self.assertIn("DOWNLOAD_POST_REQUESTS=0", status)

    def test_title_year_raw_no_extension_remains_parsable(self):
        # Authorized TorrServer filenames often have no trailing .mkv.
        transport = GetOnly({("vi", 1): ([row(7, MATCHED, "vi")], 1)})
        client = OpenSubtitles(api_key="LOCAL", transport=transport)
        name = "Example Film 2017 1080p BluRay x265-GRP"
        status = search_only_status(client, name)
        self.assertIn("PARSED_TITLE=Example Film", status)
        self.assertIn("PARSED_YEAR=2017", status)
        self.assertIn("VIDEO_RELEASE_GROUP=grp", status)
        self.assertIn("ROUTE=VI_READY", status)
        self.assertEqual(transport.urls[0]["query"], ["example film"])
        self.assertEqual(transport.calls, [("GET", "vi", 1)])

    def test_no_year_title_mode_rejects_before_provider(self):
        transport = GetOnly({})
        client = OpenSubtitles(api_key="LOCAL", transport=transport)
        with self.assertRaisesRegex(SubtitleApiError, "BAD_MEDIA_YEAR"):
            search_only_status(client, "Example Film 1080p BluRay-GRP")
        self.assertEqual(transport.calls, [])

    def test_invalid_filename_rejected_before_network(self):
        transport = GetOnly({})
        client = OpenSubtitles(api_key="PRIVATE", transport=transport)
        for name in ("", "../foo", "a\\b", "a\nb", " "):
            with self.subTest(name=name):
                with self.assertRaisesRegex(SubtitleApiError, "BAD_MEDIA_FILENAME"):
                    search_only_status(client, name, "3501632")
        self.assertEqual(transport.calls, [])

    def test_provider_control_codes_sanitized_local(self):
        out, calls = self.probe({
            ("vi", 1): ([row(4, "Example.Film.2017.1080p.BluRay.x265-GRP\x1b", "vi")], 1),
        })
        self.assertNotIn("\x1b", "\n".join(out))
        self.assertIn("DOWNLOAD_POST_REQUESTS=0", out)


if __name__ == "__main__":
    unittest.main()
