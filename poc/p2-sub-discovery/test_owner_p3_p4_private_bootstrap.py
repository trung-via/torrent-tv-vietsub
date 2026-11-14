"""Owner-scoped private P3/P4 policy + startup regressions, all synthetic.

No live PC data, provider calls, Android, LAN server, task modification or
real subtitles. Config and file paths exist only under ephemeral test roots.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

_POC = Path(__file__).resolve().parent.parent
for _part in ("p2-aisub", "p3-vietsub-trigger"):
    _path = str(_POC / _part)
    if _path not in sys.path:
        sys.path.insert(0, _path)

from owner_p3_p4_private_policy import (
    PrivateP3P4Policy, OwnerPolicyBlocked, _probe_subtitle_languages,
)
from owner_p3_p4_entrypoint import (
    main, _pair_and_stage_identity, OwnerEntrypointBlocked,
)
from owner_torrserver_readonly import OwnerTorrServerReader, OwnerLocalTorrServer


HASH = "a" * 40
PROFILE = "test-owner"
NAME = "Synthetic.Authorized.2017.1080p.BluRay-GRP.mkv"
PATH = "Authorized/" + NAME
PORT = 8090


class PrivateP3P4PolicyTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="ttv-owner-private-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.owner = self.root / "OwnerBridge"
        self.owner.mkdir()
        self.media = self.root / "approved-media"
        self.media.mkdir()
        self.video = self.media / NAME
        self.video.write_bytes(b"synthetic local media fixture only")
        self.policy_file = self.owner / "p3-p4-policy.json"
        self.item = dict(
            torrent_hash=HASH, file_index=2, torrserver_path=PATH,
            video_path=str(self.video), rights_approved=True)
        self.config = dict(
            schema="TTV-P3-P4-OWNER-POLICY-V1", enabled=True,
            profile_id=PROFILE, torrserver_port=PORT,
            private_media_root=str(self.media), media=[self.item])
        self.current_path = PATH
        self.current_length = self.video.stat().st_size
        self.reader = OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE, PORT),
            transport=self.fake_transport)

    def fake_transport(self, url, payload, timeout):
        self.assertEqual(url, "http://127.0.0.1:8090/torrents")
        self.assertEqual(json.loads(payload), {"action":"get", "hash":HASH})
        return json.dumps({
            "hash": HASH,
            "file_stats": [{
                "id":2, "path":self.current_path,
                "length":self.current_length
            }],
        }).encode()

    def policy(self, probe=lambda _: "ABSENT"):
        self.policy_file.write_text(json.dumps(self.config), encoding="utf-8")
        return PrivateP3P4Policy(
            manifest=self.policy_file, owner_root=self.owner,
            private_media_root=self.media,
            torrserver=self.reader, probe=probe)

    def test_explicit_rights_exact_torrserver_file_and_independent_vi_probe(self):
        seen = []
        policy = self.policy(probe=lambda video: seen.append(video) or "ABSENT")
        self.assertTrue(policy.owner_auto_allowed())
        self.assertTrue(policy.media_rights_allowed(PROFILE,HASH,2))
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"ABSENT")
        pinned = policy.locate_owner_pinned_files(PROFILE,HASH,2,PATH)
        self.assertEqual(pinned.video_path,self.video)
        self.assertTrue(pinned.video_file_complete)
        self.assertEqual(seen,[self.video])

    def test_missing_rights_or_disallowed_media_never_became_eligible(self):
        self.item["rights_approved"] = False
        policy=self.policy()
        self.assertFalse(policy.media_rights_allowed(PROFILE,HASH,2))
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"UNKNOWN")
        self.assertIsNone(policy.locate_owner_pinned_files(PROFILE,HASH,2,PATH))
        self.assertFalse(policy.media_rights_allowed(PROFILE,"b"*40,2))

    def test_owner_disabled_is_not_bypassed_by_valid_entry(self):
        self.config["enabled"] = False
        policy=self.policy()
        self.assertFalse(policy.owner_auto_allowed())
        self.assertFalse(policy.media_rights_allowed(PROFILE,HASH,2))
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"UNKNOWN")

    def test_changed_torrserver_path_or_size_and_modified_video_all_hold(self):
        policy=self.policy()
        self.current_path="Unauthorized/"+NAME
        self.assertFalse(policy.media_rights_allowed(PROFILE,HASH,2))
        self.current_path=PATH
        self.current_length+=3
        self.assertFalse(policy.media_rights_allowed(PROFILE,HASH,2))
        self.current_length-=3
        self.video.write_bytes(b"modified")
        self.assertFalse(policy.media_rights_allowed(PROFILE,HASH,2))

    def test_unknown_track_or_present_vi_never_activates_automatic_vi(self):
        policy=self.policy(probe=lambda _: "UNKNOWN")
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"UNKNOWN")
        policy=self.policy(probe=lambda _: "PRESENT")
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"PRESENT")
        sidecar=self.media/(self.video.stem+".vi.srt")
        sidecar.write_text("1\n00:00:01,000 --> 00:00:02,000\nVI\n")
        self.assertEqual(self.policy().verified_local_vi_state(PROFILE,HASH,2),"PRESENT")

    def test_bad_policy_schema_wrong_port_broad_rights_and_duplicate_rejected(self):
        self.config["torrserver_port"]=8091
        with self.assertRaises(OwnerPolicyBlocked):
            self.policy()
        self.config["torrserver_port"]=8090
        self.config["media"]=[self.item,self.item.copy()]
        with self.assertRaisesRegex(OwnerPolicyBlocked,"DUPLICATE"):
            self.policy()
        self.config["media"]=[self.item]
        self.config["private_media_root"]=str(self.root)
        with self.assertRaisesRegex(OwnerPolicyBlocked,"SCHEMA"):
            self.policy()

    def test_no_credentials_no_silent_policy_file_and_no_real_owner_start(self):
        with self.assertRaises(OwnerEntrypointBlocked):
            _pair_and_stage_identity(self.owner)
        with mock.patch("owner_p3_p4_entrypoint._interactive_windows_session", return_value=False):
            self.assertEqual(main(["--owner-root",str(self.owner),
                                   "--cache-root",str(self.root/"cache"),
                                   "--state-root",str(self.root/"state"),
                                   "--start-lan"]),1)
        self.assertFalse((self.owner/"p4-identity").exists())

    def test_direct_owner_script_without_pythonpath_imports_before_ci_gate(self):
        """Reproduce the installed ScheduledTask's -File/direct Python layout.

        Even on a CI runner this must reach the EXPLICIT-OWNER guard rather
        than crashing at import of lan_revision_feed / paired_activation.
        The subprocess runs only a CI-blocked import; it never binds LAN.
        """
        script = Path(__file__).resolve().parent / "owner_p3_p4_entrypoint.py"
        env = os.environ.copy()
        env.pop("PYTHONPATH", None)
        env["CI"] = "true"
        env["GITHUB_ACTIONS"] = "true"
        for mode in ("--start-lan", "--preflight-only"):
            with self.subTest(mode=mode):
                with tempfile.TemporaryDirectory(prefix="ttv-direct-owner-smoke-") as cwd:
                    result = subprocess.run(
                        [sys.executable, "-E", str(script),
                         "--owner-root", str(self.owner),
                         "--cache-root", str(self.root / "cache"),
                         "--state-root", str(self.root / "state"), mode],
                        cwd=cwd, env=env, capture_output=True, text=True,
                        timeout=15, check=False,
                    )
                self.assertEqual(result.returncode, 1, result.stderr[:250])
                self.assertIn("P3_P4_OWNER_INTERACTIVE_EXPLICIT_START_REQUIRED",
                              result.stdout)
                self.assertFalse((self.owner / "p4-identity").exists())

    def test_ffprobe_ambiguous_track_or_missing_binary_fails_closed(self):
        with mock.patch("owner_p3_p4_private_policy.subprocess.run") as proc:
            proc.return_value.returncode=0
            proc.return_value.stdout=json.dumps({"streams":[
                {"codec_type":"subtitle","tags":{"language":"und"}}
            ]}).encode()
            self.assertEqual(_probe_subtitle_languages(self.video),"UNKNOWN")
            proc.return_value.stdout=json.dumps({"streams":[
                {"codec_type":"subtitle","tags":{"language":"vie"}}
            ]}).encode()
            self.assertEqual(_probe_subtitle_languages(self.video),"PRESENT")
            proc.side_effect=OSError("synthetic ffprobe missing")
            self.assertEqual(_probe_subtitle_languages(self.video),"UNKNOWN")


if __name__ == "__main__":
    unittest.main()
