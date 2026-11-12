"""Offline tests: D2 owner VI manual selection and one POST quota bound."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from matcher import Media
from opensubtitles import OpenSubtitles, SubtitleApiError
from owner_vi_trial import _safe_display, owner_trial


SRT = (b"1\n00:00:00,500 --> 00:00:02,000\nhello\n\n"
       b"2\n00:00:03,000 --> 00:00:04,000\nworld\n")
FILE = "Sample.Film.2017.1080p.BluRay.x265-TEAM.mkv"


def row(file_id: int, release: str, language="vi", extension="ass"):
    return {"attributes": {"language": language, "release": release,
                           "files": [{"file_id": file_id, "file_name": f"candidate.{extension}"}]}}


class Fake:
    def __init__(self, *, rows=None, payload=SRT, link="https://dl.opensubtitles.com/mock/test.srt"):
        self.rows = rows if rows is not None else [
            row(30, "Sample.Film.2017.1080p.BluRay.x265"),
            row(40, "Sample.Film.2017.1080p.WEB-DL.x264-OTHER"),
            row(50, "Different.Film.2017.1080p.BluRay.x265-TEAM"),
        ]
        self.payload = payload
        self.link = link
        self.calls = []

    def __call__(self, method, url, headers, body, cap):
        self.calls.append((method, url, headers, body, cap))
        if method == "GET":
            return json.dumps({"data": self.rows, "total_count": len(self.rows)}).encode("utf-8")
        if method == "POST":
            return json.dumps({"link": self.link}).encode("utf-8")
        if method == "GET_BINARY":
            return self.payload
        raise AssertionError("Unexpected method")


def run(fake, answers, *, filename=FILE, root=None):
    prompts = list(answers)
    out = []
    client = OpenSubtitles(api_key="DO_NOT_SHARE_KEY", transport=fake)
    def ask(prompt):
        out.append(f"PROMPT={prompt}")
        return prompts.pop(0)
    status = owner_trial(client, filename, "3501632", ask=ask, emit=out.append,
                         cache_root=root)
    return status, out


class ManualTrialTests(unittest.TestCase):
    def test_local_preview_cancel_is_get_only(self):
        fake = Fake()
        status, out = run(fake, ["0"])
        self.assertEqual(status, 0)
        self.assertEqual([x[0] for x in fake.calls], ["GET"])
        self.assertIn("VI_SHORTLIST=2", out)
        self.assertIn("OWNER_CANCELLED", out)
        self.assertIn("DOWNLOAD_POST_ATTEMPTS=0", out)
        self.assertNotIn("DO_NOT_SHARE_KEY", "\n".join(out))
        self.assertNotIn("candidate.ass", "\n".join(out))

    def test_explicit_second_consent_is_required(self):
        fake = Fake()
        status, out = run(fake, ["1", "yes"])
        self.assertEqual(status, 0)
        self.assertEqual([x[0] for x in fake.calls], ["GET"])
        self.assertIn("DOWNLOAD_POST_ATTEMPTS=0", out)
        self.assertIn("OWNER_CANCELLED", out)

    def test_success_one_post_verified_srt_to_private_cache(self):
        fake = Fake()
        with tempfile.TemporaryDirectory() as temp:
            status, out = run(fake, ["1", "DOWNLOAD ONE"], root=Path(temp))
            self.assertEqual(status, 0)
            self.assertEqual([x[0] for x in fake.calls], ["GET", "POST", "GET_BINARY"])
            self.assertEqual(json.loads(fake.calls[1][3]),
                             {"file_id": 30, "sub_format": "srt"})
            self.assertNotIn("Api-Key", fake.calls[2][2])
            self.assertIn("DOWNLOAD_POST_ATTEMPTS=1", out)
            self.assertIn("DOWNLOAD_AND_SRT_QA=PASS", out)
            self.assertIn("CUES=2", out)
            self.assertIn("PRIVATE_CACHE_SAVED=YES", out)
            self.assertIn("TV_SYNC_VERIFIED=NO", out)
            self.assertEqual(len(list(Path(temp).glob("*.srt"))), 1)
            self.assertEqual(list(Path(temp).glob("*.srt"))[0].read_bytes(), SRT)
            self.assertNotIn("DO_NOT_SHARE_KEY", "\n".join(out))
            self.assertNotIn("hello", "\n".join(out))

    def test_invalid_or_bogus_choice_does_not_download(self):
        for answer in ("2x", "99", "0x1", "", "-1", "１"):
            with self.subTest(answer=answer):
                fake = Fake()
                status, out = run(fake, [answer])
                self.assertEqual(status, 1)
                self.assertEqual([x[0] for x in fake.calls], ["GET"])
                self.assertIn("INVALID_SELECTION", out)
                self.assertIn("DOWNLOAD_POST_ATTEMPTS=0", out)

    def test_no_ranked_vi_is_get_only(self):
        fake = Fake(rows=[row(10, "Different.Film.2017.1080p.BluRay.x265-TEAM")])
        status, out = run(fake, [])
        self.assertEqual(status, 0)
        self.assertIn("VI_SHORTLIST=0", out)
        self.assertIn("NEXT_GATE=NO_VI_SHORTLIST", out)
        self.assertEqual([x[0] for x in fake.calls], ["GET"])

    def test_conversion_failure_cannot_cache(self):
        fake = Fake(payload=b"[Script Info]\nwrong container")
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(SubtitleApiError, "BAD_SUBTITLE_TIMELINE"):
                run(fake, ["1", "DOWNLOAD ONE"], root=Path(temp))
            self.assertEqual([x[0] for x in fake.calls], ["GET", "POST", "GET_BINARY"])
            self.assertEqual(list(Path(temp).iterdir()), [])

    def test_manual_client_refuses_without_consent_or_bad_binding(self):
        fake = Fake()
        client = OpenSubtitles(api_key="secret", transport=fake)
        media = Media("owner", "test-hash", 0, FILE)
        disc = client.search(media, language="vi", query_mode="imdb", imdb_id="3501632")
        with self.assertRaisesRegex(SubtitleApiError, "MANUAL_CONSENT_REQUIRED"):
            client.download_manual_vi(media, disc, file_id=30)
        with self.assertRaisesRegex(SubtitleApiError, "NO_APPROVED_MANUAL_CANDIDATE"):
            client.download_manual_vi(media, disc, file_id=50, authorized=True)
        with self.assertRaisesRegex(SubtitleApiError, "NO_APPROVED_MANUAL_CANDIDATE"):
            client.download_manual_vi(media, disc, file_id=999, authorized=True)
        other = Media("owner", "different", 0, FILE)
        with self.assertRaisesRegex(SubtitleApiError, "MEDIA_BINDING_MISMATCH"):
            client.download_manual_vi(other, disc, file_id=30, authorized=True)
        self.assertEqual([x[0] for x in fake.calls], ["GET"])

    def test_remote_wrong_language_cannot_be_manually_downloaded_as_vi(self):
        fake = Fake(rows=[row(30, "Sample.Film.2017.1080p.BluRay.x265-TEAM", language="en")])
        client = OpenSubtitles(api_key="secret", transport=fake)
        media = Media("owner", "test-hash", 0, FILE)
        disc = client.search(media, language="en", query_mode="imdb", imdb_id="3501632")
        with self.assertRaisesRegex(SubtitleApiError, "NO_APPROVED_MANUAL_CANDIDATE"):
            client.download_manual_vi(media, disc, file_id=30, authorized=True)
        self.assertEqual([x[0] for x in fake.calls], ["GET"])

    def test_terminal_control_characters_are_sanitized(self):
        label = _safe_display("title\x1b[31m\n injected\t")
        self.assertNotIn("\x1b", label)
        self.assertNotIn("\n", label)
        self.assertLessEqual(len(label), 150)

    def test_invalid_media_name_rejected_before_api(self):
        for filename in ("", "../sample.mkv", "a\\b.mkv", "a\nb.mkv"):
            with self.subTest(filename=filename):
                fake = Fake()
                with self.assertRaisesRegex(SubtitleApiError, "BAD_MEDIA_FILENAME"):
                    run(fake, [], filename=filename)
                self.assertEqual(fake.calls, [])


if __name__ == "__main__":
    unittest.main()
