"""Offline-only acceptance for automatic, resumable LEAN120 EN -> VI -> P4.

All source lines and model responses are synthetic; NEVER contact Gemini,
OpenSubtitles, the TV, a LAN socket or a real user file during CI.
"""
from __future__ import annotations

from dataclasses import replace
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from automatic_lean120_worker import AutomaticLean120Worker
from assumed_source_handoff import AssumedEnglishSubtitle
from cue_pipeline import parse_cues
from lan_revision_feed import SessionRevisionFeed
from lean120_api import ModelProfile

MEDIA = "media." + "a" * 64
OTHER = "media." + "b" * 64
PROFILE = ModelProfile("gemini", "gemini-4-hydrogen", "high")


def source_srt(n: int) -> bytes:
    lines = []
    for i in range(1, n + 1):
        sec = i - 1
        hours, rem = divmod(sec, 3600)
        mins, seconds = divmod(rem, 60)
        a = f"{hours:02d}:{mins:02d}:{seconds:02d}"
        lines.append(
            f"{i}\n{a},000 --> {a},900\nSynthetic English cue {i}\n"
        )
    return ("\n".join(lines) + "\n").encode("utf-8")


def handoff(n: int = 242, media: str = MEDIA) -> AssumedEnglishSubtitle:
    return AssumedEnglishSubtitle.from_supplied(
        media_key=media, fmt="srt", source_bytes=source_srt(n)
    )


def fake_response(ids) -> dict:
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


class FakeGemini:
    def __init__(self):
        self.calls = []
        self.fail_on = None

    def __call__(self, url, headers, body, timeout):
        payload = json.loads(body)
        self_has_key = headers.get("x-goog-api-key")
        assert self_has_key == "fake-test-key"
        assert url.endswith("/gemini-4-hydrogen:generateContent")
        assert payload["generationConfig"]["thinkingConfig"]["thinkingLevel"] == "HIGH"
        ids = [x["id"] for x in json.loads(
            payload["contents"][0]["parts"][0]["text"])["target"]]
        self.calls.append(tuple(ids))
        if self.fail_on == len(self.calls):
            raise ValueError("GEMINI_TRANSPORT_FAILED")
        return fake_response(ids)


class AutoLean120WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "private-state"
        self.provider = FakeGemini()

    def worker(self, **kwargs):
        return AutomaticLean120Worker(
            state_root=kwargs.pop("state_root", self.root),
            profile=kwargs.pop("profile", PROFILE),
            glossary=kwargs.pop("glossary", {"Fictional": "Hư cấu"}),
            api_key=kwargs.pop("api_key", "fake-test-key"),
            transport=kwargs.pop("transport", self.provider),
        )

    def folders(self):
        return list(self.root.iterdir())

    def test_automatic_120_240_242_private_final_vietsub_and_p4_feed(self):
        source = handoff(242)
        feed = SessionRevisionFeed(
            session_id="SyntheticSession0123456789", media_key=MEDIA,
            source_sha256=source.source_sha256, pairing_secret=b"a" * 32,
        )
        emitted = []
        def publish(revision):
            emitted.append(revision)
            return feed.publish(revision)
        final = self.worker().run(source, on_revision=publish)
        self.assertEqual([r.translated_count for r in emitted], [120, 240, 242])
        self.assertEqual([r.version for r in emitted], [1, 2, 3])
        self.assertTrue(final.complete)
        self.assertEqual(len(self.provider.calls), 3)
        self.assertEqual(len(self.provider.calls[0]), 120)
        self.assertEqual(self.provider.calls[1][0], 121)
        original = parse_cues(source.source_bytes, "srt")
        translated = parse_cues(final.payload, "srt")
        self.assertEqual([c.number for c in original], [c.number for c in translated])
        self.assertEqual([(c.start_ms, c.end_ms) for c in original],
                         [(c.start_ms, c.end_ms) for c in translated])
        self.assertEqual(translated[130].text, "Phụ đề kiểm thử 131")
        self.assertEqual(json.loads(feed.latest())["translated_count"], 242)
        self.assertEqual(len(self.folders()), 1)
        saved = self.folders()[0] / "vi-final.srt"
        self.assertEqual(saved.read_bytes(), final.payload)
        self.assertFalse((self.folders()[0] / "active.lock").exists())
        for f in self.folders()[0].glob("*.json"):
            self.assertNotIn("fake-test-key", f.read_text(encoding="utf-8"))
            self.assertNotIn(MEDIA, f.name)
        self.assertFalse(list(self.folders()[0].glob("*.inflight")))

    def test_reuse_completed_batch_never_calls_provider_again(self):
        source = handoff(241)
        self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 3)
        emit = []
        final = self.worker().run(source, on_revision=emit.append)
        self.assertTrue(final.complete)
        self.assertEqual([r.translated_count for r in emit], [120, 240, 241])
        self.assertEqual(len(self.provider.calls), 3)

    def test_interruption_stops_unknown_provider_effects_no_auto_retry(self):
        source = handoff(241)
        self.provider.fail_on = 2
        emitted = []
        with self.assertRaisesRegex(ValueError, "GEMINI_TRANSPORT_FAILED"):
            self.worker().run(source, on_revision=emitted.append)
        self.assertEqual([r.translated_count for r in emitted], [120])
        self.assertEqual(len(self.provider.calls), 2)
        job = self.folders()[0]
        self.assertTrue((job / "batch-0001.json").is_file())
        self.assertTrue((job / "batch-0002.inflight").is_file())
        self.assertFalse((job / "batch-0002.json").exists())
        self.assertFalse((job / "vi-final.srt").exists())
        with self.assertRaisesRegex(ValueError, "UNCERTAIN_BATCH_MANUAL_RECONCILE"):
            self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 2)

    def test_checkpoint_then_publish_failure_is_replayed_without_api(self):
        source = handoff(125)
        def crashed(_):
            raise ValueError("P4_SUBSCRIBER_DISCONNECTED")
        with self.assertRaisesRegex(ValueError, "P4_SUBSCRIBER_DISCONNECTED"):
            self.worker().run(source, on_revision=crashed)
        self.assertEqual(len(self.provider.calls), 1)
        job = self.folders()[0]
        self.assertTrue((job / "batch-0001.json").is_file())
        got = []
        final = self.worker().run(source, on_revision=got.append)
        self.assertTrue(final.complete)
        self.assertEqual([x.translated_count for x in got], [120, 125])
        self.assertEqual(len(self.provider.calls), 2)

    def test_committed_checkpoint_with_old_inflight_marker_is_recoverable(self):
        source = handoff(122)
        self.worker().run(source)
        job = self.folders()[0]
        marker = job / "batch-0001.inflight"
        marker.write_text("TTV-P2-TEST-STALE-INFLIGHT", encoding="utf-8")
        self.worker().run(source)
        self.assertFalse(marker.exists())
        self.assertEqual(len(self.provider.calls), 2)

    def test_corrupt_checkpoint_fails_closed_without_new_billing(self):
        source = handoff(121)
        self.worker().run(source)
        job = self.folders()[0]
        cp = job / "batch-0001.json"
        data = json.loads(cp.read_text(encoding="utf-8"))
        data["translations"][0]["vi"] = "Tampered but well-formed"
        cp.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "CHECKPOINT_DIGEST_MISMATCH"):
            self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 2)

    def test_existing_lock_blocks_second_worker_without_network(self):
        source = handoff(1)
        self.worker().run(source)
        job = self.folders()[0]
        (job / "active.lock").write_text("another process owns lock", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 1)

    def test_bad_handoff_glossary_or_key_cannot_call_api(self):
        src = handoff(2)
        bad = replace(src, source_bytes=source_srt(1))
        with self.assertRaisesRegex(ValueError, "AUTO_LEAN120_SOURCE_CHANGED"):
            self.worker().run(bad)
        with self.assertRaisesRegex(ValueError, "AUTHORIZED_EN_HANDOFF_REQUIRED"):
            self.worker().run(replace(src, source_status="UNVERIFIED_OPEN_SUBTITLE"))
        with self.assertRaisesRegex(ValueError, "LEAN120_GLOSSARY_INVALID"):
            self.worker(glossary={"X": "Y" * 200}).run(src)
        with self.assertRaisesRegex(ValueError, "GEMINI_API_KEY_REQUIRED"):
            self.worker(api_key="")
        with self.assertRaisesRegex(ValueError, "ABSOLUTE_PRIVATE_STATE_REQUIRED"):
            self.worker(state_root=Path("relative"))
        self.assertEqual(self.provider.calls, [])
        self.assertFalse(self.root.exists())

    def test_profile_change_and_media_identity_create_isolated_jobs(self):
        src = handoff(1)
        self.worker().run(src)
        low = ModelProfile("gemini", "gemini-4-hydrogen", "low")
        self.worker(profile=low).run(src)
        self.worker().run(handoff(1, OTHER))
        self.assertEqual(len(self.folders()), 3)
        self.assertEqual(len(self.provider.calls), 3)

    def test_many_cues_are_progressive_no_manual_batch_stepping(self):
        src = handoff(1761)
        final = self.worker().run(src)
        self.assertTrue(final.complete)
        self.assertEqual(final.total_count, 1761)
        self.assertEqual(final.translated_count, 1761)
        self.assertEqual(len(self.provider.calls), 15)
        self.assertEqual(len(parse_cues(final.payload, "srt")), 1761)
        self.assertTrue((self.folders()[0] / "vi-final.srt").is_file())


if __name__ == "__main__":
    unittest.main()
