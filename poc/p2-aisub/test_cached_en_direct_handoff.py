"""Offline source-to-worker bridge tests. No OpenSubtitles/Gemini/TV calls."""
from __future__ import annotations

from dataclasses import replace
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from automatic_lean120_worker import AutomaticLean120Worker
from cached_en_direct_handoff import (
    CachedEnReceipt, prepare_local_translation_source, run_local_translation,
)
from cue_pipeline import parse_cues
from lean120_api import ModelProfile, _https_post

PROFILE = ModelProfile("gemini", "gemini-4-hydrogen", "high")


def synthetic_srt(count: int = 125) -> bytes:
    lines = []
    for ordinal in range(1, count + 1):
        tick = ordinal - 1
        hour, rem = divmod(tick, 3600)
        minute, second = divmod(rem, 60)
        start = f"{hour:02}:{minute:02}:{second:02}"
        lines.append(
            f"{ordinal}\n{start},000 --> {start},900\nTest English {ordinal}"
        )
    return ("\n\n".join(lines) + "\n").encode("utf-8")


class FakeWorker:
    def __init__(self):
        self.calls = []
    def run(self, source, *, on_revision):
        self.calls.append((source, on_revision))
        return "TRANSLATION_FAKE_OK"


class FakeGemini:
    def __init__(self):
        self.calls = []
    def __call__(self, url, headers, body, timeout):
        data = json.loads(body)
        cues = json.loads(data["contents"][0]["parts"][0]["text"])["target"]
        ids = [cue["id"] for cue in cues]
        self.calls.append(ids)
        return {
            "candidates": [{
                "finishReason": "STOP",
                "content": {"parts": [{
                    "text": json.dumps({"translations": [
                        {"id": i, "vi": f"Phụ đề kiểm thử {i}"} for i in ids
                    ]}, ensure_ascii=False)
                }]}
            }]
        }


class CachedEnBridgeTests(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory()
        self.addCleanup(t.cleanup)
        self.root = Path(t.name).resolve()
        self.cache = self.root / "subtitle-trials"
        self.cache.mkdir()
        self.source_file = self.cache / "synthetic-en.srt"
        self.content = synthetic_srt()
        self.source_file.write_bytes(self.content)
        self.receipt = CachedEnReceipt(
            self.source_file, hashlib.sha256(self.content).hexdigest(), 125
        )

    def test_prepare_direct_source_revalidates_source_without_extra_files(self):
        original = sorted(x.name for x in self.cache.iterdir())
        source = prepare_local_translation_source(self.receipt, private_root=self.cache)
        self.assertEqual(source.source_sha256, self.receipt.source_sha256)
        self.assertEqual(source.cue_count, 125)
        self.assertEqual(source.source_bytes, self.content)
        self.assertRegex(source.media_key, r"^media\.[0-9a-f]{64}$")
        self.assertEqual(
            source.media_key,
            prepare_local_translation_source(self.receipt,
                                             private_root=self.cache).media_key)
        self.assertEqual([x.name for x in self.cache.iterdir()], original)

    def test_translation_only_requires_approval_and_never_calls_tv(self):
        fake = FakeWorker()
        with self.assertRaisesRegex(ValueError, "CLOUD_UPLOAD_AUTHORIZATION_REQUIRED"):
            run_local_translation(self.receipt, private_root=self.cache,
                                  worker=fake)
        self.assertEqual(fake.calls, [])
        output = run_local_translation(
            self.receipt, private_root=self.cache, worker=fake,
            cloud_upload_authorized=True
        )
        self.assertEqual(output, "TRANSLATION_FAKE_OK")
        self.assertEqual(len(fake.calls), 1)
        self.assertIsNone(fake.calls[0][1])  # on_revision MUST be None
        self.assertEqual(fake.calls[0][0].cue_count, 125)

    def test_real_existing_lean120_worker_mocked_in_same_process(self):
        provider = FakeGemini()
        worker = AutomaticLean120Worker(
            state_root=self.root / "checkpoint-only",
            profile=PROFILE,
            glossary={"Fictional": "Hư cấu"},
            api_key="synthetic-only",
            transport=provider,
        )
        with mock.patch.dict("os.environ", {"CI": "true"}):
            final = run_local_translation(
                self.receipt, private_root=self.cache, worker=worker,
                cloud_upload_authorized=True,
            )
        self.assertTrue(final.complete)
        self.assertEqual(final.translated_count, 125)
        self.assertEqual([len(x) for x in provider.calls], [120, 5])
        source = parse_cues(self.content, "srt")
        translated = parse_cues(final.payload, "srt")
        self.assertEqual(
            [(x.number, x.start_ms, x.end_ms) for x in source],
            [(x.number, x.start_ms, x.end_ms) for x in translated],
        )
        self.assertIn(b"1\n", final.payload)
        self.assertEqual(len(list((self.root / "checkpoint-only").rglob("vi-final.srt"))), 1)
        self.assertFalse(list(self.cache.glob("verified-en-manifest.json")))
        self.assertEqual(list(self.cache.iterdir()), [self.source_file])
        # Re-entry with same owner source and profile reuses verified checkpoints;
        # no second model request and no second OpenSubtitles request.
        with mock.patch.dict("os.environ", {"CI": "true"}):
            replay = run_local_translation(
                self.receipt, private_root=self.cache, worker=worker,
                cloud_upload_authorized=True,
            )
        self.assertTrue(replay.complete)
        self.assertEqual([len(x) for x in provider.calls], [120, 5])

    def test_reject_live_transport_in_ci(self):
        worker = AutomaticLean120Worker(
            state_root=self.root / "state",
            profile=PROFILE,
            glossary={},
            api_key="fake",
            transport=_https_post,
        )
        with mock.patch.dict("os.environ", {"CI": "true"}):
            with self.assertRaisesRegex(ValueError, "LIVE_PROVIDER_FORBIDDEN_IN_CI"):
                run_local_translation(self.receipt, private_root=self.cache,
                                      worker=worker, cloud_upload_authorized=True)
        self.assertFalse((self.root / "state").exists())

    def test_changed_source_sha_rejected_before_worker_call(self):
        fake = FakeWorker()
        self.source_file.write_bytes(self.content + b"\nchanged")
        with self.assertRaisesRegex(ValueError, "SHA256_MISMATCH"):
            run_local_translation(self.receipt, private_root=self.cache,
                                  worker=fake, cloud_upload_authorized=True)
        self.assertEqual(fake.calls, [])

    def test_expected_cue_count_mismatch(self):
        changed = replace(self.receipt, cue_count=124)
        with self.assertRaisesRegex(ValueError, "CUE_COUNT_MISMATCH"):
            prepare_local_translation_source(changed, private_root=self.cache)

    def test_wrong_language_rejected_even_if_bytes_srt(self):
        changed = replace(self.receipt, language="vi")
        with self.assertRaisesRegex(ValueError, "RECEIPT_INVALID"):
            prepare_local_translation_source(changed, private_root=self.cache)

    def test_non_srt_or_non_timed_source_rejected(self):
        renamed = self.cache / "payload.txt"
        renamed.write_bytes(self.content)
        r = replace(self.receipt, cache_file=renamed)
        with self.assertRaisesRegex(ValueError, "PRIVATE_FILE_REQUIRED"):
            prepare_local_translation_source(r, private_root=self.cache)
        self.source_file.write_bytes(b"invalid")
        r2 = replace(self.receipt,
                     source_sha256=hashlib.sha256(b"invalid").hexdigest(),
                     cue_count=1)
        with self.assertRaises(ValueError):
            prepare_local_translation_source(r2, private_root=self.cache)

    def test_outside_root_and_symlink_rejected(self):
        external = self.root / "elsewhere.srt"
        external.write_bytes(self.content)
        changed = replace(self.receipt, cache_file=external)
        with self.assertRaisesRegex(ValueError, "OUTSIDE_PRIVATE_ROOT"):
            prepare_local_translation_source(changed, private_root=self.cache)
        link = self.cache / "linked.srt"
        try:
            link.symlink_to(self.source_file)
        except (OSError, NotImplementedError):
            return
        changed = replace(self.receipt, cache_file=link)
        with self.assertRaisesRegex(ValueError, "PRIVATE_FILE_REQUIRED"):
            prepare_local_translation_source(changed, private_root=self.cache)

    def test_bad_receipt_and_size_early_fail(self):
        values = [
            replace(self.receipt, source_sha256="x" * 64),
            replace(self.receipt, cue_count=0),
            replace(self.receipt, cue_count=True),
            replace(self.receipt, language="und"),
        ]
        for r in values:
            with self.subTest(r=r):
                with self.assertRaisesRegex(ValueError, "RECEIPT_INVALID"):
                    prepare_local_translation_source(r, private_root=self.cache)


if __name__ == "__main__":
    unittest.main()
