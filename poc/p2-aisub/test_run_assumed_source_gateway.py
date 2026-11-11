"""No-network tests for the explicitly started PC source→API gateway."""
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from run_assumed_source_gateway import build_controller
from paired_activation import activation_request_mac

MASTER=b"synthetic-pairing-device-key-32x"
MEDIA="media."+"a"*64


class PCGatewayBootstrapTests(unittest.TestCase):
    def test_assumed_source_requires_exact_key_and_valid_file_before_any_server(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"already-matched.srt"
            path.write_bytes(b"1\n00:00:01,000 --> 00:00:01,850\nSynthetic English\n")
            profile=Path(__file__).with_name("translator_profile.json")
            with mock.patch("run_assumed_source_gateway.create_paired_server",create=True) as server:
                gateway=build_controller(
                    media_key=MEDIA,source_file=path,master_hex=MASTER.hex(),
                    execute_api=False,profile_file=profile,api_key="")
                nonce="6"*32
                activated=gateway.activate({
                    "schema":"TTV-P4-ACTIVATE-V1",
                    "media_key":MEDIA,"nonce":nonce,
                    "auth":activation_request_mac(MASTER,MEDIA,nonce)})
                self.assertEqual(activated["media_key"],MEDIA)
                self.assertIsNone(gateway.feed_for(activated["session_id"]).latest())
                server.assert_not_called()
            with self.assertRaisesRegex(ValueError,"GEMINI_API_KEY_ENV_REQUIRED"):
                build_controller(media_key=MEDIA,source_file=path,
                    master_hex=MASTER.hex(),execute_api=True,
                    profile_file=profile,api_key="")
            with self.assertRaisesRegex(ValueError,"P4_DEVICE_PAIRING_KEY_REQUIRED"):
                build_controller(media_key=MEDIA,source_file=path,
                    master_hex="short",execute_api=False,
                    profile_file=profile,api_key="")
            with self.assertRaisesRegex(ValueError,"P4_TIMED_SOURCE_FILE_REQUIRED"):
                build_controller(media_key=MEDIA,source_file=Path(tmp)/"missing.srt",
                    master_hex=MASTER.hex(),execute_api=False,
                    profile_file=profile,api_key="")

    def test_import_never_starts_server_or_calls_api(self):
        import run_assumed_source_gateway as module
        self.assertTrue(callable(module.main))
        self.assertNotIn("serve_forever(",module.build_controller.__code__.co_names)
        self.assertFalse(hasattr(module,"SERVER_RUNNING"))


if __name__=="__main__":unittest.main()
