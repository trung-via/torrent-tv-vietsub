"""Tests the VI fast socket timeout without real network/provider quota."""
import unittest
import urllib.error
from unittest.mock import patch

from matcher import Media
from opensubtitles import OpenSubtitles, SubtitleApiError


class Opener:
    def __init__(self):
        self.timeouts = []
    def open(self, request, timeout=0):
        self.timeouts.append(timeout)
        raise urllib.error.URLError("synthetic network failure")


class SocketTimeoutTests(unittest.TestCase):
    def test_vi_short_timeout_reaches_real_urllib_transport(self):
        opener = Opener()
        media = Media("owner", "synthetic", 0, "Example.Film.2017.1080p.BluRay.x265-GRP.mkv")
        client = OpenSubtitles(api_key="local-test-only")
        with patch("opensubtitles.urllib.request.build_opener", return_value=opener):
            with self.assertRaisesRegex(SubtitleApiError, "API_NETWORK_ERROR"):
                client.search(media, language="vi", query_mode="imdb",
                              imdb_id="3501632", timeout_seconds=4.0)
        self.assertEqual(opener.timeouts, [4.0])

    def test_default_search_timeout_unchanged(self):
        opener = Opener()
        media = Media("owner", "synthetic", 0, "Example.Film.2017.1080p.BluRay.x265-GRP.mkv")
        client = OpenSubtitles(api_key="local-test-only")
        with patch("opensubtitles.urllib.request.build_opener", return_value=opener):
            with self.assertRaisesRegex(SubtitleApiError, "API_NETWORK_ERROR"):
                client.search(media, language="en", query_mode="imdb", imdb_id="3501632")
        self.assertEqual(opener.timeouts, [15.0])


if __name__ == "__main__":
    unittest.main()
