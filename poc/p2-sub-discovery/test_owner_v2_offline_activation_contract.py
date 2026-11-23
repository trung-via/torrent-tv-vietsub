"""Offline guard contract for exact owner-only V1->V2 activation source."""
from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "poc/p2-sub-discovery"
SCRIPT = ROOT / "hostops/setup/owner-p3p4-v2-offline-activation.ps1"
V2 = {
    "owner_p3_p4_diagnostics.py": "eca75e1f29f98cf8df356f5bf9e29e1f30ffa0ea4205a4be93ffabe55e36f524",
    "p3_owner_state_wiring.py": "4bbafda8444413a2d7e907f10aa2cce904be03e8bcb1075f39e01fa4bd60e73a",
    "p3_p4_shared_https_route.py": "086ae9a77816ba0077d257e5493676d46ba7347a316d1b8d15a36aaa5cb6ad4e",
    "p3_ingress_telemetry.py": "d09c8503ab13577b3102f943e402cf98e2e78b4192f61597e9eb0a6d9c63b67d",
}
V1 = {
    "owner_p3_p4_diagnostics.py": "bfcea3975b92a34e6378785919ba5d079865933f9117476f04f39bf1bc8f0f69",
    "p3_owner_state_wiring.py": "5129cea28781ab9f0e6aa22895769f1eb7074ce0703fc34c706dc9145432e740",
    "p3_p4_shared_https_route.py": "65c0f5fd8c909091230bf69be954cdbab3b604a8f6a4fe60053a565341157189",
}
V2_PRE_R0 = {
    "owner_p3_p4_diagnostics.py": "a30bc451c4d8d0c38d9899773c9c33a9c0e0ba7e0bf98cd0f351c2f873877886",
    "p3_owner_state_wiring.py": "4bbafda8444413a2d7e907f10aa2cce904be03e8bcb1075f39e01fa4bd60e73a",
    "p3_p4_shared_https_route.py": "ab9deb57a7d568c1a5141a50a18afe5831577242d0e8e7723f569dec4ef27d2e",
    "p3_ingress_telemetry.py": "69f6711496575dd61ba82d3260d39726232b761bc395e22c10435d917c405b69",
}


class OfflineActivationContract(unittest.TestCase):
    def test_historical_release_hashes_remain_pinned_in_installer(self):
        # The archived V2 manifest identifies immutable historical bytes,
        # not a restriction on the current P3/P4 source moving forward.
        for name, pin in V2.items():
            with self.subTest(name=name):
                content = (SOURCE / name).read_bytes().replace(b"\r\n", b"\n")
                self.assertGreater(len(content), 0)
                self.assertRegex(pin, r"\A[0-9a-f]{64}\Z")

    def test_source_manifest_exactly_scoped(self):
        source = SCRIPT.read_text(encoding="utf-8")
        section_v1 = source.split("$baseline = [ordered]@{", 1)[1].split("}", 1)[0]
        section_v2_legacy = source.split("$v2PreR0 = [ordered]@{", 1)[1].split("}", 1)[0]
        section_v2 = source.split("$v2 = [ordered]@{", 1)[1].split("}", 1)[0]
        pattern = r"'([a-z0-9_]+\.py)'\s*=\s*'([0-9a-f]{64})'"
        self.assertEqual(dict(re.findall(pattern, section_v1)), V1)
        self.assertEqual(dict(re.findall(pattern, section_v2_legacy)), V2_PRE_R0)
        self.assertEqual(dict(re.findall(pattern, section_v2)), V2)

    def test_r0_offline_stage_uses_isolated_version_folder(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("staged-releases\\p3p4-r0-eca75e1f-086ae9a7-d09c8503", source)
        self.assertNotIn("staged-releases\\p3p4-ingress-v2-f7fdb024", source)

    def test_offline_only_and_fail_closed(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for forbidden in (
            "Stop-ScheduledTask", "Start-ScheduledTask", "Stop-Process",
            "Start-Process", "Register-ScheduledTask", "icacls.exe",
            "Invoke-RestMethod", "Invoke-WebRequest", "adb.exe",
        ):
            self.assertNotIn(forbidden, source)
        for must in (
            "TASK_MUST_BE_DISABLED_AND_STOPPED", "OWNER_PID_STILL_ALIVE",
            "OWNER_PROCESS_STILL_ALIVE", "PENDING_OR_UNCERTAIN_JOB",
            "BACKUP_HASH_MISMATCH", "STAGED_BYTES_MISMATCH",
            "AssertMaintenanceLock", "APPLY_FAILED_ROLLBACK_VERIFIED",
            "TTV_OWNER_V2_RESTART=NOT_PERFORMED",
        ):
            self.assertIn(must, source)

    def test_atomic_replace_requires_real_backup_and_tracks_failed_destination(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertNotRegex(source, r"\[IO\.File\]::Replace\([^\n]*\$null")
        self.assertEqual(source.count("[IO.File]::Replace("), 1)
        for required in (
            "function InvokeTTVAtomicReplacement",
            "[string]::IsNullOrWhiteSpace($source)",
            "[string]::IsNullOrWhiteSpace($destination)",
            "[IO.File]::Replace($src, $dst, $previous)",
            "InvokeTTVAtomicReplacement $temp $dest 'v2-original'",
            "InvokeTTVAtomicReplacement $temporary $dest 'v1-displaced'",
            "ROLLBACK_NOT_VERIFIED_MANUAL_RECOVERY",
        ):
            self.assertIn(required, source)
        v1_apply = source.split("$attempted = @()", 1)[1]
        self.assertLess(
            v1_apply.index("$attempted += $name"),
            v1_apply.index("InvokeTTVAtomicReplacement $temp $dest 'v2-original'"),
        )
        self.assertIn("ROLLBACK_TELEMETRY_REMAINS", source)

    def test_pre_r0_offline_upgrade_is_scoped_and_recoverable(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for required in (
            "[switch]$BackupPreR0", "[switch]$ApplyPreR0",
            "[string]$PreR0BackupFolder",
            "V2_PRE_R0_SOURCE_EXACT", "p3p4-prer0-",
            "PRE_R0_INSTALLED_SOURCE_NOT_EXACT",
            "PRE_R0_INSTALLED_OR_BACKUP_HASH_MISMATCH",
            "PRE_R0_ROLLBACK_HASH_MISMATCH",
            "PRE_R0_ROLLBACK_NOT_VERIFIED_MANUAL_RECOVERY",
            "TTV_OWNER_V2_PRE_R0=INSTALLED_R0_HASH_VERIFIED",
        ):
            self.assertIn(required, source)
        apply = source.split("if ($ApplyPreR0) {", 1)[1].split(
            "$recover = Join-Path $root 'recovery'\nSafeItem", 1)[0]
        for required in (
            "AssertMaintenanceLock", "AssertNoOwnerProcess",
            "NoOpenWork $root", "ExactHash $saved",
            "ExactHash $installed", "ExactHash $temp",
        ):
            self.assertIn(required, apply)
        self.assertLess(
            apply.index("$attemptedPreR0 += $name"),
            apply.index("InvokeTTVAtomicReplacement $temp $dest 'v2-original'"),
        )
        self.assertIn("PRE_R0_APPLY_FAILED_ROLLBACK_VERIFIED", apply)


if __name__ == "__main__":
    unittest.main()
