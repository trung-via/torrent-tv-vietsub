"""Offline owner-approved exact EN downloader tests; no real OpenSubtitles calls."""
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

from opensubtitles import OpenSubtitles, SubtitleApiError
from owner_en_single_trial import download_one_exact_en

VIDEO = "Example.Film.2017.1080p.BluRay.x265-GRP"
NORMAL = "Example.Film.2017.1080p.BluRay.x265-GRP_eng"
SDH = NORMAL + " SDH"
WRONG = "Example.Film.2017.1080p.BluRay.x264-OTHER_eng"
SRT = b"1\n00:00:01,000 --> 00:00:02,000\nHello\n"


def row(number, name, language):
    return {"attributes": {"language": language, "release": name,
                            "files": [{"file_id": number, "file_name": "unverified.ass"}]}}


class Provider:
    def __init__(self, vi=(), en=None, *, broken=None):
        self.vi = tuple(vi)
        self.en = tuple(en) if en is not None else (row(7, NORMAL, "en"), row(8, SDH, "en"))
        self.calls = []
        self.broken = broken

    def __call__(self, method, url, headers, body, cap):
        self.calls.append((method, url, body))
        if method == "GET":
            q = parse_qs(urlsplit(url).query)
            lang = q["languages"][0]
            rows = self.vi if lang == "vi" else self.en
            return json.dumps({"data": list(rows), "total_count": len(rows)}).encode()
        if method == "POST":
            if self.broken == "POST":
                raise SubtitleApiError("API_NETWORK_ERROR")
            return json.dumps({"link": "https://dl.opensubtitles.com/local/fixture.srt"}).encode()
        if method == "GET_BINARY":
            return b"invalid" if self.broken == "SRT" else SRT
        raise AssertionError("bad method")


def run(provider, root, *, expected=NORMAL, reply="DOWNLOAD ONE",
        video=VIDEO, group="grp"):
    messages = []
    code = download_one_exact_en(
        OpenSubtitles(api_key="TEST_PRIVATE_KEY", transport=provider),
        video, expected, group, ask=lambda prompt: reply,
        emit=messages.append, cache_root=root)
    return code, messages


class ExactEnTests(unittest.TestCase):
    def test_success_one_post_non_sdh_and_cache(self):
        api = Provider()
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            code, messages = run(api, root)
            self.assertEqual(code, 0)
            self.assertEqual([x[0] for x in api.calls],
                             ["GET", "GET", "POST", "GET_BINARY"])
            self.assertEqual(json.loads(api.calls[2][2]),
                             {"file_id": 7, "sub_format": "srt"})
            self.assertIn("ROUTE=EN_TRANSLATE", messages)
            self.assertIn("EXACT_RELEASE_MATCH=YES", messages)
            self.assertIn("EN_STANDARD_NOT_SDH=YES", messages)
            self.assertIn("EN_WINNER_SCORE=97", messages)
            self.assertIn("DOWNLOAD_POST_ATTEMPTS=1", messages)
            self.assertIn("SRT_CUES=1", messages)
            self.assertIn("DOWNLOAD_AND_SRT_QA=PASS", messages)
            self.assertIn("PRIVATE_CACHE_SAVED=YES", messages)
            self.assertIn("AI_TEXT_UPLOADED=NO", messages)
            self.assertEqual(len(list(root.glob("*.srt"))), 1)
            self.assertEqual(list(root.glob("*.srt"))[0].read_bytes(), SRT)
            self.assertEqual(len(list(root.glob(".en-once-*"))), 1)
            self.assertNotIn("TEST_PRIVATE_KEY", "\n".join(messages))

    def test_owner_cancel_no_post_no_claim(self):
        api = Provider()
        with tempfile.TemporaryDirectory() as path:
            _, msgs = run(api, Path(path), reply="no")
            self.assertIn("OWNER_CANCELLED", msgs)
            self.assertEqual([x[0] for x in api.calls], ["GET", "GET"])
            self.assertEqual(list(Path(path).iterdir()), [])

    def test_sdh_only_must_not_use_en_without_exact_normal(self):
        api = Provider(en=(row(8, SDH, "en"),))
        with tempfile.TemporaryDirectory() as path:
            _, msgs = run(api, Path(path))
            self.assertIn("EXPECTED_STANDARD_EN_NOT_SELECTED", msgs)
            self.assertEqual([x[0] for x in api.calls], ["GET", "GET"])
            self.assertEqual(list(Path(path).iterdir()), [])

    def test_provider_changed_non_sdh_filename_does_not_spend_post(self):
        api = Provider(en=(row(9, WRONG, "en"),))
        with tempfile.TemporaryDirectory() as path:
            _, msgs = run(api, Path(path))
            self.assertEqual(msgs[-1], "NEXT_GATE=SOURCE_REVIEW_NO_DOWNLOAD")
            self.assertEqual([x[0] for x in api.calls], ["GET", "GET"])

    def test_vi_confident_aborts_en_only_approval(self):
        api = Provider(vi=(row(11, "Example.Film.2017.1080p.BluRay.x265-GRP_vi", "vi"),))
        with tempfile.TemporaryDirectory() as path:
            _, msgs = run(api, Path(path))
            self.assertIn("ROUTE=VI_READY", msgs)
            self.assertEqual([x[0] for x in api.calls], ["GET"])

    def test_invalid_target_and_group_rejected_before_search(self):
        for video, expected, group in (
            ("../bad", NORMAL, "grp"), (VIDEO, "a\nb", "grp"),
            (VIDEO, NORMAL, "OTHER"), (VIDEO, NORMAL, "bad-name"),
        ):
            api = Provider()
            with self.subTest(video=video, group=group):
                with tempfile.TemporaryDirectory() as path:
                    with self.assertRaises(SubtitleApiError):
                        run(api, Path(path), video=video, expected=expected, group=group)
                self.assertEqual(api.calls, [])

    def test_post_failure_persists_no_retry_across_invocations(self):
        api = Provider(broken="POST")
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            with self.assertRaisesRegex(SubtitleApiError, "API_NETWORK_ERROR"):
                run(api, root)
            self.assertEqual([x[0] for x in api.calls], ["GET", "GET", "POST"])
            self.assertEqual(len(list(root.glob(".en-once-*"))), 1)
            with self.assertRaisesRegex(SubtitleApiError,
                                        "EN_DOWNLOAD_ALREADY_ATTEMPTED"):
                run(api, root)
            self.assertEqual([x[0] for x in api.calls],
                             ["GET", "GET", "POST", "GET", "GET"])
            self.assertEqual(list(root.glob("*.srt")), [])

    def test_srt_bad_persists_latch_and_never_cache(self):
        api = Provider(broken="SRT")
        with tempfile.TemporaryDirectory() as path:
            with self.assertRaises(SubtitleApiError):
                run(api, Path(path))
            self.assertEqual([x[0] for x in api.calls],
                             ["GET", "GET", "POST", "GET_BINARY"])
            self.assertEqual(list(Path(path).glob("*.srt")), [])
            self.assertEqual(len(list(Path(path).glob(".en-once-*"))), 1)

    def test_preflight_bad_directory_aborts_before_post(self):
        api = Provider()
        with tempfile.TemporaryDirectory() as path:
            root = Path(path) / "not-a-directory"
            root.write_text("file")
            with self.assertRaises(OSError):
                run(api, root)
            self.assertEqual([x[0] for x in api.calls], ["GET", "GET"])


if __name__ == "__main__":
    unittest.main()
