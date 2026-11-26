"""Synthetic native callback tests: no Windows/browser/provider effects."""
from dataclasses import replace
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
