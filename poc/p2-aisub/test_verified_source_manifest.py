"""Offline exact-owner-source manifest and authenticated P4 handoff tests."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from paired_activation import PairedActivation, activation_request_mac
from run_assumed_source_gateway import build_controller
from verified_source_manifest import verified_source_from_manifest

MEDIA = "media." + "a" * 64
OTHER = "media." + "b" * 64
SECRET = b"synthetic-pairing-device-key-32x"
assert len(SECRET) == 32


def fixture() -> bytes:
    return b"1\n00:00:01,000 --> 00:00:02,000\nSynthetic English sentence\n"


class VerifiedSourceManifestTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "owner-en.srt"
        self.source.write_bytes(fixture())
        self.manifest = self.root / "verified-owner.json"
        self.entry = {
            "media_key": MEDIA, "format": "srt",
            "source_path": str(self.source),
            "source_sha256": hashlib.sha256(fixture()).hexdigest(),
            "owner_confirmed_match": True,
        }
        self.write_manifest()

    def write_manifest(self, entries=None):
        self.manifest.write_text(json.dumps({
            "schema": "TTV-P2-OWNER-MATCHED-EN-V1",
            "sources": [self.entry] if entries is None else entries,
        }), encoding="utf-8")

    def request(self, media=MEDIA, nonce="1"*32, secret=SECRET):
        return {
            "schema": "TTV-P4-ACTIVATE-V1", "media_key": media,
            "nonce": nonce, "auth": activation_request_mac(secret, media, nonce),
        }

    def test_exact_media_manifest_uses_original_sha_and_fixed_srt(self):
        h = verified_source_from_manifest(self.manifest, MEDIA)
        self.assertEqual(h.media_key, MEDIA)
        self.assertEqual(h.cue_count, 1)
        self.assertEqual(h.source_bytes, fixture())
        self.assertEqual(h.source_sha256, self.entry["source_sha256"])
        with self.assertRaisesRegex(ValueError, "SOURCE_NOT_FOUND"):
            verified_source_from_manifest(self.manifest, OTHER)

    def test_manifest_checks_fail_closed_for_wrong_source_or_authority(self):
        samples = [
            {**self.entry, "owner_confirmed_match": False},
            {**self.entry, "source_sha256": "0"*64},
            {**self.entry, "source_path": "relative-file.srt"},
            {**self.entry, "format": "vtt"},
            {**self.entry, "unexpected": True},
            {**self.entry, "media_key": OTHER},
        ]
        for entry in samples:
            with self.subTest(entry=entry):
                self.write_manifest([entry])
                with self.assertRaises(ValueError):
                    verified_source_from_manifest(self.manifest, MEDIA)
        self.write_manifest([self.entry, self.entry])
        with self.assertRaisesRegex(ValueError, "ROW_INVALID"):
            verified_source_from_manifest(self.manifest, MEDIA)
        self.write_manifest()
        self.source.write_bytes(fixture() + b"malicious change")
        with self.assertRaisesRegex(ValueError, "HASH_MISMATCH"):
            verified_source_from_manifest(self.manifest, MEDIA)

    def test_gateway_manifest_is_exact_hmac_gated_before_file_read(self):
        calls = []
        def factory(media):
            calls.append(media)
            return verified_source_from_manifest(self.manifest, media)
        controller = PairedActivation(
            device_secret=SECRET, supplied={},
            authenticated_source_factory=factory)
        with self.assertRaisesRegex(ValueError, "AUTH_INVALID"):
            controller.activate(self.request(secret=b"x"*32))
        self.assertEqual(calls, [])
        with self.assertRaisesRegex(ValueError, "SOURCE_NOT_FOUND"):
            controller.activate(self.request(media=OTHER, nonce="2"*32))
        self.assertEqual(calls, [OTHER])
        activated = controller.activate(self.request())
        self.assertEqual(activated["media_key"], MEDIA)
        self.assertEqual(activated["source_sha256"], self.entry["source_sha256"])
        self.assertIsNotNone(controller.feed_for(activated["session_id"]))

    def test_real_registry_cannot_use_untrusted_mock_or_missing_consent(self):
        profile = Path(__file__).with_name("translator_profile.json")
        with self.assertRaisesRegex(ValueError, "P2_OWNER_SOURCE_MANIFEST_SCOPE_INVALID"):
            build_controller(
                media_key=MEDIA, source_file=None, source_manifest=self.manifest,
                master_hex=SECRET.hex(), execute_api=True,
                profile_file=profile, api_key="synthetic",
                auto_state_dir=self.root/"private")
        with self.assertRaisesRegex(ValueError, "P2_OWNER_SOURCE_MANIFEST_SCOPE_INVALID"):
            build_controller(
                media_key=None, source_file=None, source_manifest=self.manifest,
                master_hex=SECRET.hex(), execute_api=False,
                profile_file=profile, api_key="synthetic",
                auto_state_dir=self.root/"private")
        with self.assertRaisesRegex(ValueError, "P2_AUTO_PRIVATE_STATE_DIR_REQUIRED"):
            build_controller(
                media_key=None, source_file=None, source_manifest=self.manifest,
                master_hex=SECRET.hex(), execute_api=True,
                profile_file=profile, api_key="synthetic")

    def test_verified_source_by_tv_activation_starts_automatic_worker(self):
        from threading import Event
        flag = Event()
        invocations = []
        class FakeWorker:
            def __init__(self, **kwargs):
                invocations.append(("ctor", kwargs["profile"].model))
            def run(self, handoff, on_revision=None):
                invocations.append(("run", handoff.media_key, handoff.cue_count))
                flag.set()
                class Result:
                    translated_count = 1
                return Result()
        profile = Path(__file__).with_name("translator_profile.json")
        with mock.patch("run_assumed_source_gateway.AutomaticLean120Worker", FakeWorker):
            controller = build_controller(
                media_key=None, source_file=None, source_manifest=self.manifest,
                master_hex=SECRET.hex(), execute_api=True,
                profile_file=profile, api_key="synthetic",
                auto_state_dir=self.root/"private")
            self.assertEqual(invocations, [])  # No model invocation on setup.
            controller.activate(self.request(nonce="3"*32))
            self.assertTrue(flag.wait(3.0))
        self.assertIn(("run", MEDIA, 1), invocations)


if __name__ == "__main__":
    unittest.main()
