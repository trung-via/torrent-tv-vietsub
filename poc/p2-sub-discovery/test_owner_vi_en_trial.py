"""Owner local VI-first or matched EN fallback: GET-only until explicit consent."""
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

from opensubtitles import OpenSubtitles, SubtitleApiError
from owner_vi_en_trial import owner_fallback_trial

MEDIA = "Example.Film.2017.1080p.BluRay.x265-GROUP.mkv"
SAME = "Example.Film.2017.1080p.BluRay.x265-GROUP"
WEAK = "Example.Film.2017.WEB-DL.x264-OTHER"
SRT = b"1\n00:00:01,000 --> 00:00:03,000\nHello\n"


def row(file_id, language, release):
    return {"attributes": {"language": language, "release": release,
                            "files": [{"file_id": file_id, "file_name": "source.ass"}]}}


class Fake:
    def __init__(self, vi=None, en=None, *, content=SRT):
        self.vi = vi or []
        self.en = en or []
        self.calls = []
        self.content = content

    def __call__(self, method, url, headers, body, cap):
        self.calls.append((method, url))
        if method == "GET":
            query = parse_qs(urlsplit(url).query)
            lang = query["languages"][0]
            rows = self.vi if lang == "vi" else self.en
            return json.dumps({"data": rows, "total_count": len(rows)}).encode()
        if method == "POST":
            return json.dumps({"link": "https://dl.opensubtitles.com/test/accepted.srt"}).encode()
        if method == "GET_BINARY":
            return self.content
        raise AssertionError("unexpected transport")


def run(fake, answer, root):
    messages = []
    def ask(prompt):
        return answer
    result = owner_fallback_trial(
        OpenSubtitles(api_key="private-key", transport=fake),
        MEDIA, "3501632", ask=ask, emit=messages.append, cache_root=root)
    return result, messages


class TrialTests(unittest.TestCase):
    def test_vi_priority_and_no_en_search(self):
        fake = Fake(vi=[row(5, "vi", SAME)], en=[row(7, "en", SAME)])
        with tempfile.TemporaryDirectory() as root:
            code, lines = run(fake, "no", Path(root))
            self.assertEqual(code, 0)
            self.assertIn("ROUTE=VI_READY", lines)
            self.assertIn("OWNER_CANCELLED", lines)
            self.assertEqual([x[0] for x in fake.calls], ["GET"])
            self.assertEqual(len(list(Path(root).iterdir())), 0)

    def test_weak_vi_confident_en_single_post_and_private_cache(self):
        fake = Fake(vi=[row(5, "vi", WEAK)], en=[row(7, "en", SAME)])
        with tempfile.TemporaryDirectory() as root:
            code, lines = run(fake, "DOWNLOAD ONE", Path(root))
            self.assertEqual(code, 0)
            self.assertEqual([x[0] for x in fake.calls],
                             ["GET", "GET", "POST", "GET_BINARY"])
            self.assertIn("ROUTE=EN_TRANSLATE", lines)
            self.assertIn("SRT_LANGUAGE=EN", lines)
            self.assertIn("DOWNLOAD_SRT_QA=PASS", lines)
            self.assertIn("AI_TEXT_UPLOADED=NO", lines)
            self.assertIn("NEXT_GATE=EN_TRANSLATION_PROVIDER_AUTHORIZATION", lines)
            self.assertEqual(len(list(Path(root).glob("*.srt"))), 1)
            self.assertEqual(list(Path(root).glob("*.srt"))[0].read_bytes(), SRT)
            self.assertNotIn("private-key", "\n".join(lines))

    def test_ambiguous_en_reviewer_no_download(self):
        fake = Fake(en=[row(7, "en", SAME), row(8, "en", SAME)])
        with tempfile.TemporaryDirectory() as root:
            code, lines = run(fake, "DOWNLOAD ONE", Path(root))
            self.assertEqual(code, 0)
            self.assertIn("ROUTE=REVIEW_REQUIRED", lines)
            self.assertEqual([x[0] for x in fake.calls], ["GET", "GET"])
            self.assertIn("DOWNLOAD_POST_ATTEMPTS=0", lines)

    def test_no_match_does_not_download(self):
        fake = Fake()
        with tempfile.TemporaryDirectory() as root:
            code, lines = run(fake, "DOWNLOAD ONE", Path(root))
            self.assertEqual(code, 0)
            self.assertIn("ROUTE=NO_MATCH", lines)
            self.assertEqual([x[0] for x in fake.calls], ["GET", "GET"])

    def test_invalid_en_srt_fails_without_cache(self):
        fake = Fake(en=[row(7, "en", SAME)], content=b"invalid")
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(SubtitleApiError):
                run(fake, "DOWNLOAD ONE", Path(root))
            self.assertEqual([x[0] for x in fake.calls],
                             ["GET", "GET", "POST", "GET_BINARY"])
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_cache_preflight_before_download(self):
        fake = Fake(en=[row(7, "en", SAME)])
        with tempfile.TemporaryDirectory() as root:
            bad_root = Path(root) / "not_a_dir"
            bad_root.write_text("already file")
            with self.assertRaises(OSError):
                run(fake, "DOWNLOAD ONE", bad_root)
            self.assertEqual([x[0] for x in fake.calls], ["GET", "GET"])

    def test_invalid_filename_stops_before_network(self):
        for value in ("", "../foo", "C:\\test\\file", "a\nb"):
            fake = Fake(en=[row(7, "en", SAME)])
            client = OpenSubtitles(api_key="key", transport=fake)
            with self.subTest(value=value):
                with self.assertRaisesRegex(SubtitleApiError,
                                            "BAD_MEDIA_FILENAME"):
                    owner_fallback_trial(client, value, "3501632",
                                         ask=lambda _: "DOWNLOAD ONE")
            self.assertEqual(fake.calls, [])


if __name__ == "__main__":
    unittest.main()
