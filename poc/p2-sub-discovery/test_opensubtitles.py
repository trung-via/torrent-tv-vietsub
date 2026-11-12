"""Offline contract tests for D2: never contact provider or TV."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

from matcher import Media
from opensubtitles import (
    Asset, OpenSubtitles, SubtitleApiError, _safe_https, parse_search_response,
    validate_timed_text, write_private_cache,
)


SRT = b"1\n00:00:01,000 --> 00:00:02,500\nHello\n\n2\n00:00:03,000 --> 00:00:04,000\nWorld\n"
VTT = b"WEBVTT\n\n00:01.000 --> 00:02.500\nHello\n\n00:03.000 --> 00:04.000\nWorld\n"


def media(index=0, movie_hash=None):
    return Media("synthetic-profile", "synthetic-hash", index,
                 "Sample.Film.2017.1080p.BluRay.x265-TEAM.mkv", movie_hash=movie_hash)


def row(file_id=81, *, language="vi", release="Sample.Film.2017.1080p.BluRay.x265-TEAM",
        matched=False, name="sample.srt"):
    return {"type": "subtitle", "attributes": {
        "language": language, "release": release, "moviehash_match": matched,
        "files": [{"file_id": file_id, "file_name": name}]}}


def response(*rows):
    return json.dumps({"data": list(rows)}).encode("utf-8")


class FakeTransport:
    def __init__(self, *, search=None, link="https://dl.opensubtitles.com/mock/81.srt",
                 content=SRT, error=None):
        self.search = search or response(row())
        self.link = link
        self.content = content
        self.calls = []
        self.error = error

    def __call__(self, method, url, headers, body, cap):
        self.calls.append((method, url, headers, body, cap))
        if self.error is not None:
            raise SubtitleApiError(self.error)
        if method == "GET":
            return self.search
        if method == "POST":
            return json.dumps({"link": self.link, "remaining": 17}).encode("utf-8")
        if method == "GET_BINARY":
            return self.content
        raise AssertionError("unexpected method")


class D2Tests(unittest.TestCase):
    def test_free_first_query_and_headers(self):
        mock = FakeTransport()
        disc = OpenSubtitles(api_key="synthetic-key", transport=mock).search(media(), language="vi")
        self.assertEqual(disc.decision.status, "VI_MATCH")
        method, url, headers, body, cap = mock.calls[0]
        qs = parse_qs(urlsplit(url).query)
        self.assertEqual(method, "GET")
        self.assertEqual(qs["languages"], ["vi"])
        self.assertEqual(qs["year"], ["2017"])
        self.assertEqual(qs["query"], ["Sample.Film.2017.1080p.BluRay.x265-TEAM"])
        self.assertEqual(headers["Api-Key"], "synthetic-key")
        self.assertIn("TorrentTVVietsub", headers["User-Agent"])
        self.assertIsNone(body)

    def test_verified_hash_query_and_priority(self):
        mock = FakeTransport(search=response(
            row(81, language="vi", release="Sample.Film.2017.1080p.BluRay.x265-TEAM"),
            row(82, language="vi", release="Sample.Film.2017.WEB-DL.x264-OTHER", matched=True)))
        m = media(movie_hash="0102030405060708")
        d = OpenSubtitles(api_key="x", transport=mock).search(m, language="vi")
        self.assertEqual(d.decision.winner.subtitle_id, "82")
        self.assertEqual(parse_qs(urlsplit(mock.calls[0][1]).query)["moviehash"], ["0102030405060708"])

    def test_download_once_then_validates(self):
        mock = FakeTransport()
        client = OpenSubtitles(api_key="x", transport=mock)
        m = media()
        disc = client.search(m, language="vi")
        asset = client.download_selected(m, disc)
        self.assertEqual([x[0] for x in mock.calls], ["GET", "POST", "GET_BINARY"])
        self.assertEqual(json.loads(mock.calls[1][3]), {"file_id": 81})
        self.assertNotIn("Api-Key", mock.calls[2][2])
        self.assertEqual((asset.language, asset.cues, asset.contents), ("vi", 2, SRT))

    def test_english_fallback_no_translation_call(self):
        mock = FakeTransport(search=response(row(3, language="en")))
        client = OpenSubtitles(api_key="x", transport=mock)
        m = media()
        disc = client.search(m, language="en")
        self.assertEqual(disc.decision.status, "EN_TRANSLATE")
        self.assertEqual(client.download_selected(m, disc).language, "en")
        self.assertEqual(len(mock.calls), 3)

    def test_search_filters_unexpected_other_language(self):
        mock = FakeTransport(search=response(row(81, language="en"), row(82, language="vi")))
        client = OpenSubtitles(api_key="x", transport=mock)
        found = client.search(media(), language="vi")
        self.assertEqual([c.file_id for c in found.candidates], [82])
        self.assertEqual(found.decision.status, "VI_MATCH")

    def test_header_control_characters_rejected(self):
        for token in ("bad" + chr(10) + "header", "bad" + chr(13) + "header"):
            with self.assertRaisesRegex(SubtitleApiError, "INVALID_BEARER_TOKEN"):
                OpenSubtitles(api_key="x", bearer=token)
        with self.assertRaisesRegex(SubtitleApiError, "API_KEY_NOT_CONFIGURED"):
            OpenSubtitles(api_key="bad" + chr(10) + "header")

    def test_bad_key_or_language_no_request(self):
        with self.assertRaisesRegex(SubtitleApiError, "API_KEY_NOT_CONFIGURED"):
            OpenSubtitles(api_key="")
        mock = FakeTransport()
        with self.assertRaisesRegex(SubtitleApiError, "UNSUPPORTED_LANGUAGE"):
            OpenSubtitles(api_key="x", transport=mock).search(media(), language="fr")
        self.assertEqual(mock.calls, [])

    def test_confidence_gate_blocks_quota_consumption(self):
        mock = FakeTransport(search=response(row(release="Sample.Film.2017.1080p.WEB-DL.x264-OTHER")))
        client = OpenSubtitles(api_key="x", transport=mock)
        m = media()
        disc = client.search(m, language="vi")
        self.assertEqual(disc.decision.status, "REVIEW_REQUIRED")
        with self.assertRaisesRegex(SubtitleApiError, "NO_APPROVED_DOWNLOAD"):
            client.download_selected(m, disc)
        self.assertEqual(len(mock.calls), 1)

    def test_wrong_media_binding(self):
        mock = FakeTransport()
        client = OpenSubtitles(api_key="x", transport=mock)
        disc = client.search(media(0), language="vi")
        with self.assertRaisesRegex(SubtitleApiError, "MEDIA_BINDING_MISMATCH"):
            client.download_selected(media(1), disc)
        self.assertEqual(len(mock.calls), 1)

    def test_duplicate_file_id_deduplicated(self):
        d = parse_search_response(media(), response(row(), row()))
        self.assertEqual(len(d.candidates), 1)

    def test_bad_search_response(self):
        for body in (b'[]', b'{"data":{}}', b'bad', b'{"data":[1]}'):
            if body == b'{"data":[1]}':
                self.assertEqual(len(parse_search_response(media(), body).candidates), 0)
            else:
                with self.assertRaises(SubtitleApiError):
                    parse_search_response(media(), body)

    def test_unknown_format_and_language_skipped(self):
        d = parse_search_response(media(), response(
            row(1, name="a.zip"), row(2, language="fr"), row(3, name="movie.vtt")))
        self.assertEqual([x.file_id for x in d.candidates], [3])

    def test_raw_rows_with_unsupported_extensions_explain_zero_candidates(self):
        # Regression from Human-reported OpenSubtitles response with nonzero
        # rows but zero admitted files. Exact reason remains unverified live.
        d = parse_search_response(media(), response(
            row(1, name="Sample.Film.2017.sub"),
            row(2, name="Sample.Film.2017.txt"),
            {"attributes": {"language": "vi", "files": []}},
        ))
        self.assertEqual(d.raw_rows, 3)
        self.assertEqual(len(d.candidates), 0)
        reasons = dict(d.parse_rejections)
        self.assertEqual(reasons["unsupported_extension"], 2)
        self.assertEqual(reasons["missing_files"], 1)
        self.assertEqual(d.decision.status, "NO_MATCH")

    def test_parser_counts_invalid_schema_without_leaking_values(self):
        secret_title = "Private.User.Release.2017"
        data = json.dumps({"total_count": 4, "data": [
            {"attributes": {"language": "unknown", "release": secret_title,
                            "files": [{"file_id": 8, "file_name": secret_title + ".srt"}]}},
            {"attributes": {"language": "en", "files": [{"file_id": -1, "file_name": "x.srt"}]}},
            {"attributes": {"language": "en", "files": [{"file_id": 3, "file_name": ""}]}},
            {"attributes": {"language": "en", "release": secret_title, "files": []}},
        ]}).encode()
        d = parse_search_response(media(), data)
        self.assertEqual(d.raw_rows, 4)
        self.assertEqual(d.api_total, 4)
        self.assertEqual(len(d.candidates), 0)
        self.assertEqual(dict(d.parse_rejections)["unexpected_language"], 1)
        self.assertEqual(dict(d.parse_rejections)["invalid_file_id"], 1)
        self.assertEqual(dict(d.parse_rejections)["missing_file_name"], 1)
        self.assertEqual(dict(d.parse_rejections)["missing_files"], 1)
        self.assertNotIn(secret_title, str(d.parse_rejections))

    def test_no_untrusted_download_link_or_quota_chaining(self):
        for url in ("http://dl.opensubtitles.com/sub.srt",
                    "https://evil.example.com/sub.srt",
                    "https://dl.opensubtitles.com.evil.example/sub.srt",
                    "https://user:pass@dl.opensubtitles.com/sub.srt",
                    "https://dl.opensubtitles.com:8443/sub.srt"):
            mock = FakeTransport(link=url)
            cli = OpenSubtitles(api_key="x", transport=mock)
            m = media()
            disc = cli.search(m, language="vi")
            with self.assertRaisesRegex(SubtitleApiError, "UNTRUSTED_URL"):
                cli.download_selected(m, disc)
            self.assertEqual([x[0] for x in mock.calls], ["GET", "POST"])

    def test_bad_subtitle_data_rejected(self):
        for contents in (b"\xff\xfe", b"1\nnot a time\nHello\n",
                         b"", b"1\n00:00:02,000 --> 00:00:01,000\nbackwards\n",
                         b"<script>alert(1)</script>\n"):
            with self.assertRaises(SubtitleApiError):
                validate_timed_text(contents, "srt")
        self.assertEqual(validate_timed_text(SRT, "srt"), 2)
        self.assertEqual(validate_timed_text(VTT, "vtt"), 2)

    def test_download_bad_payload_never_cache(self):
        mock = FakeTransport(content=b"not-srt")
        cli = OpenSubtitles(api_key="x", transport=mock)
        m = media()
        d = cli.search(m, language="vi")
        with self.assertRaises(SubtitleApiError):
            cli.download_selected(m, d)

    def test_quotas_and_auth_errors_safe(self):
        for code in ("RATE_LIMITED_429", "API_AUTH_DENIED", "API_NETWORK_ERROR"):
            mock = FakeTransport(error=code)
            cli = OpenSubtitles(api_key="x", transport=mock)
            with self.assertRaisesRegex(SubtitleApiError, code):
                cli.search(media(), language="vi")

    def test_private_cache_is_content_addressed_and_idempotent(self):
        a = Asset(81, "vi", "srt", SRT, hashlib.sha256(SRT).hexdigest(), 2)
        with tempfile.TemporaryDirectory() as root:
            p = write_private_cache(Path(root), media(), a)
            self.assertEqual(p.read_bytes(), SRT)
            self.assertEqual(write_private_cache(Path(root), media(), a), p)
            p2 = write_private_cache(Path(root), media(1), a)
            self.assertNotEqual(p, p2)
            self.assertNotIn("Sample.Film", p.name)
            self.assertNotIn("synthetic-profile", p.name)

    def test_cache_corruption_detected(self):
        a = Asset(81, "vi", "srt", SRT, hashlib.sha256(SRT).hexdigest(), 2)
        with tempfile.TemporaryDirectory() as root:
            dest = write_private_cache(Path(root), media(), a)
            dest.write_bytes(b"tampered")
            with self.assertRaisesRegex(SubtitleApiError, "CACHE_COLLISION"):
                write_private_cache(Path(root), media(), a)

    def test_no_expiring_link_in_cache(self):
        mock = FakeTransport()
        cli = OpenSubtitles(api_key="x", transport=mock)
        m = media()
        asset = cli.download_selected(m, cli.search(m, language="vi"))
        with tempfile.TemporaryDirectory() as root:
            p = write_private_cache(Path(root), m, asset)
            self.assertNotIn("opensubtitles", str(p))
            self.assertEqual(p.read_bytes(), SRT)


if __name__ == "__main__":
    unittest.main()
