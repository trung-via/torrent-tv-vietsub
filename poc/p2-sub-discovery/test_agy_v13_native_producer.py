"""Synthetic native callback tests: no Windows/browser/provider effects."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from threading import Event
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from agy_opensubtitles_acquisition import AgyEnglishUnavailable
from agy_v13_browser_evidence import BrowserRequest, make_v13_acquirer
from agy_v13_native_producer import (
    NativeBrowserProducer, measured_metadata, native_cache_verified,
)
from test_agy_v13_browser_evidence import MEDIA, proof


class NativeProducerTests(unittest.TestCase):
    def test_measured_metadata(self):
        self.assertEqual(measured_metadata(b'{"format":{"duration":"7200"},"streams":[{"codec_type":"video","avg_frame_rate":"24/1"}]}'), (7200, 24))
        for raw in (b'{}', b'{"format":{"duration":"7200"},"streams":[{"codec_type":"video","avg_frame_rate":"0/0"}]}'):
            with self.assertRaises(AgyEnglishUnavailable):
                measured_metadata(raw)

    def test_one_call_retained_evidence_and_cache_receipt(self):
        calls = []
        def execute(*args):
            calls.append(args)
            return proof()
        with TemporaryDirectory() as temp:
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            acquire = make_v13_acquirer(producer)
            first = acquire(MEDIA, root)
            second = acquire(MEDIA, root)
            self.assertEqual(first, second)
            self.assertEqual(len(calls), 1)
            self.assertTrue(native_cache_verified(root, MEDIA, first.sha256, first.cues))
            self.assertFalse(native_cache_verified(root, replace(MEDIA, file_index=3), first.sha256, first.cues))

    def test_other_film_waits_for_browser_without_dropping_request(self):
        entered, release = Event(), Event()
        calls = []
        def execute(req, *args):
            calls.append(req.media.file_index)
            if req.media == MEDIA:
                entered.set()
                if not release.wait(5):
                    raise AssertionError("test did not release browser")
            return replace(proof(), media=req.media)
        with TemporaryDirectory() as temp:
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            with ThreadPoolExecutor(max_workers=2) as workers:
                a = workers.submit(producer, BrowserRequest(MEDIA), root)
                self.assertTrue(entered.wait(2))
                b = workers.submit(producer, BrowserRequest(replace(MEDIA, file_index=3)), root)
                try:
                    self.assertEqual(calls, [2])
                finally:
                    release.set()
                self.assertEqual(a.result(timeout=5).media.file_index, 2)
                self.assertEqual(b.result(timeout=5).media.file_index, 3)
            self.assertEqual(calls, [2, 3])

    def test_completed_invalid_source_does_not_block_other_films(self):
        calls = []
        def execute(req, *args):
            calls.append(req.media.file_index)
            return replace(proof(), media=req.media, fresh_download_verified=req.media.file_index != 2)
        with TemporaryDirectory() as temp:
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            with self.assertRaisesRegex(AgyEnglishUnavailable, "SOURCE_REJECTED"):
                producer(BrowserRequest(MEDIA), root)
            self.assertFalse((root / ".native-v13/browser.pending").exists())
            self.assertTrue(list(root.rglob("terminal.json")))
            with self.assertRaises(AgyEnglishUnavailable):
                producer(BrowserRequest(MEDIA), root)
            self.assertEqual(producer(BrowserRequest(replace(MEDIA, file_index=3)), root).media.file_index, 3)
            self.assertEqual(calls, [2, 3])

    def test_unknown_effect_blocks_same_and_other_media(self):
        calls = []
        def execute(*args):
            calls.append(args)
            raise TimeoutError()
        with TemporaryDirectory() as temp:
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            for media in (MEDIA, MEDIA, replace(MEDIA, file_index=3)):
                with self.assertRaises(AgyEnglishUnavailable):
                    producer(BrowserRequest(media), root)
            self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
