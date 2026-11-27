"""Offline API contract for one consented confident English subtitle download."""
import hashlib
import json
import unittest

from matcher import Media
from opensubtitles import OpenSubtitles, SubtitleApiError

VIDEO = "Example.Film.2017.1080p.BluRay.x265-GROUP.mkv"
SAME = "Example.Film.2017.1080p.BluRay.x265-GROUP"
WEAK = "Example.Film.2017.WEB-DL.x264-OTHER"
SRT = b"1\n00:00:01,000 --> 00:00:02,500\nHello world!\n"


class Fake:
    def __init__(self, *, release=SAME, lang="en", body=SRT):
        self.calls = []
        self.release, self.lang, self.body = release, lang, body

    def __call__(self, method, url, headers, body, cap):
        self.calls.append((method, url, headers, body))
        if method == "GET":
            return json.dumps({"data": [{"attributes": {
                "language": self.lang, "release": self.release,
                "files": [{"file_id": 77, "file_name": "subtitle.ass"}]}}]}).encode()
        if method == "POST":
            return json.dumps({"link": "https://dl.opensubtitles.com/temp/77.srt"}).encode()
        if method == "GET_BINARY":
            return self.body
        raise AssertionError("unexpected transport operation")


def setup(*, release=SAME, lang="en", body=SRT):
    fake = Fake(release=release, lang=lang, body=body)
    client = OpenSubtitles(api_key="PRIVATE", transport=fake)
    media = Media("owner-profile", "actual-infohash-placeholder", 0, VIDEO)
    d = client.search(media, language=lang, query_mode="imdb", imdb_id="3501632")
    return client, media, d, fake


class DownloadTests(unittest.TestCase):
    def test_confident_en_one_post_with_explicit_consent(self):
        client, media, d, fake = setup()
        self.assertEqual(d.decision.status, "EN_TRANSLATE")
        asset = client.download_manual_en(media, d, file_id=77, authorized=True)
        self.assertEqual(asset.language, "en")
        self.assertEqual(asset.fmt, "srt")
        self.assertEqual(asset.cues, 1)
        self.assertEqual(asset.sha256, hashlib.sha256(SRT).hexdigest())
        self.assertEqual([r[0] for r in fake.calls], ["GET", "POST", "GET_BINARY"])
        self.assertEqual(json.loads(fake.calls[1][3]),
                         {"file_id": 77, "sub_format": "srt"})
        self.assertNotIn("Api-Key", fake.calls[2][2])

    def test_no_consent_no_post(self):
        client, media, d, fake = setup()
        with self.assertRaisesRegex(SubtitleApiError, "MANUAL_CONSENT_REQUIRED"):
            client.download_manual_en(media, d, file_id=77)
        self.assertEqual([r[0] for r in fake.calls], ["GET"])

    def test_weak_en_does_not_download(self):
        client, media, d, fake = setup(release=WEAK)
        self.assertEqual(d.decision.status, "REVIEW_REQUIRED")
        with self.assertRaisesRegex(SubtitleApiError, "NO_CONFIDENT_EN_CANDIDATE"):
            client.download_manual_en(media, d, file_id=77, authorized=True)
        self.assertEqual([r[0] for r in fake.calls], ["GET"])

    def test_wrong_media_and_file_id_block_post(self):
        client, media, d, fake = setup()
        other = Media("other", media.torrent_hash, 0, media.filename)
        with self.assertRaisesRegex(SubtitleApiError, "MEDIA_BINDING_MISMATCH"):
            client.download_manual_en(other, d, file_id=77, authorized=True)
        with self.assertRaisesRegex(SubtitleApiError, "NO_CONFIDENT_EN_CANDIDATE"):
            client.download_manual_en(media, d, file_id=1, authorized=True)
        self.assertEqual([r[0] for r in fake.calls], ["GET"])

    def test_one_post_latched_even_if_invalid_srt(self):
        client, media, d, fake = setup(body=b"invalid")
        with self.assertRaisesRegex(SubtitleApiError, "BAD_SUBTITLE_TIMELINE"):
            client.download_manual_en(media, d, file_id=77, authorized=True)
        with self.assertRaisesRegex(SubtitleApiError,
                                    "MANUAL_DOWNLOAD_ALREADY_ATTEMPTED"):
            client.download_manual_en(media, d, file_id=77, authorized=True)
        self.assertEqual([r[0] for r in fake.calls], ["GET", "POST", "GET_BINARY"])

    def test_vi_then_en_cannot_double_spend_quota_in_session(self):
        client, media, en_discovery, fake = setup()
        vi_fake = Fake(release=SAME, lang="vi")
        # Separate search is enough to prove use of the same client latch.
        vi_search_response = json.dumps({"data": [{"attributes": {
            "language": "vi", "release": SAME,
            "files": [{"file_id": 77, "file_name": "subtitle.ass"}]}}]}).encode()
        def transport(method, url, headers, body, cap):
            if method == "GET":
                return vi_search_response
            return fake(method, url, headers, body, cap)
        client._transport = transport
        vi_d = client.search(media, language="vi", query_mode="imdb", imdb_id="3501632")
        client.download_manual_vi(media, vi_d, file_id=77, authorized=True)
        with self.assertRaisesRegex(SubtitleApiError,
                                    "MANUAL_DOWNLOAD_ALREADY_ATTEMPTED"):
            client.download_manual_en(media, en_discovery, file_id=77, authorized=True)
        self.assertEqual([r[0] for r in fake.calls], ["GET", "POST", "GET_BINARY"])


if __name__ == "__main__":
    unittest.main()
