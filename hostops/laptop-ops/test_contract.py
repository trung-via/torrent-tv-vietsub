"""Source-only laptop HostOps contract. No Windows, network, Owner or provider."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "hostops/laptop-ops/manifests/current.json"
ALLOWED = {"diagnostics", "owner-maintenance", "development",
           "app-maintenance", "device-lan"}


class LaptopOpsContractTests(unittest.TestCase):
    def test_only_source_pinned_routine_operation(self):
        raw = MANIFEST.read_bytes()
        self.assertLess(len(raw), 8192)
        manifest = json.loads(raw)
        self.assertEqual(set(manifest), {
            "schema", "operation", "risk", "category", "script_path",
            "script_sha256", "arguments",
        })
        self.assertEqual(manifest["schema"], "TTV-LAPTOP-HOSTOPS-OPERATION-V1")
        self.assertEqual(manifest["risk"], "ROUTINE")
        self.assertIn(manifest["category"], ALLOWED)
        self.assertRegex(manifest["operation"], r"^[a-z][a-z0-9-]{2,60}$")
        self.assertRegex(manifest["script_path"],
                         r"^hostops/laptop-ops/operations/[a-z][a-z0-9-]*\.ps1$")
        self.assertRegex(manifest["script_sha256"], r"^[0-9a-f]{64}$")
        self.assertIsInstance(manifest["arguments"], list)
        self.assertLessEqual(len(manifest["arguments"]), 8)
        for argument in manifest["arguments"]:
            self.assertRegex(argument, r"^-[A-Za-z][A-Za-z0-9]{0,39}$")
        script = (ROOT / manifest["script_path"]).resolve(strict=True)
        self.assertTrue(script.is_file())
        # Windows checkout is CRLF, but the Owner downloads exact LF Git blob
        # bytes via raw.githubusercontent.com. Hash Git, not the worktree.
        exact_bytes = subprocess.run(
            ["git", "show", "HEAD:" + manifest["script_path"]],
            cwd=ROOT, check=True, capture_output=True,
        ).stdout
        self.assertEqual(hashlib.sha256(exact_bytes).hexdigest(),
                         manifest["script_sha256"])

    def test_no_arbitrary_issues_command_or_admin_task(self):
        helper = (ROOT / "hostops/setup/owner-laptop-ops-helper.ps1").read_text()
        dispatcher = (ROOT / "hostops/jobs/owner-laptop-ops-dispatch.ps1").read_text()
        enrollment = (ROOT / "hostops/setup/enroll-owner-laptop-ops.ps1").read_text()
        self.assertIn("TTV-LAPTOP-HOSTOPS-REQUEST-V1", helper)
        self.assertIn("TTV-LAPTOP-HOSTOPS-RECEIPT-V1", dispatcher)
        self.assertIn("$manifest.risk -cne 'ROUTINE'", helper)
        self.assertIn("$manifest.risk -cne 'ROUTINE'", dispatcher)
        self.assertIn("-RunLevel Limited", enrollment)
        self.assertNotIn("-RunLevel Highest", enrollment)
        self.assertNotIn("Invoke-Expression", helper + dispatcher + enrollment)
        self.assertIn("FAILED_NO_RETRY", helper)
        self.assertIn("FAILED_NO_RETRY", dispatcher)

    def test_owner_owned_receipt_is_archived_without_service_delete(self):
        dispatcher = (ROOT / "hostops/jobs/owner-laptop-ops-dispatch.ps1").read_text()
        self.assertIn("HOSTOPS_OWNER_OPS_PREVIOUS_REQUEST_ARCHIVE_MISSING", dispatcher)
        self.assertIn("HOSTOPS_OWNER_OPS_RECEIPT_ARCHIVE_HASH_MISMATCH", dispatcher)
        self.assertIn("Copy-Item -LiteralPath $receiptFile -Destination $oldReceiptArchive", dispatcher)
        self.assertNotIn("Move-Item -LiteralPath $receiptFile", dispatcher)

    def test_first_operation_installer_pin(self):
        operation = (ROOT / "hostops/laptop-ops/operations/owner-full-diagnostics-install.ps1").read_text()
        self.assertIn("b92926714199fa986c29b48202460d903a518025", operation)
        self.assertIn("d1877e7a3f25c026252f9bcdfb9b308a27d4008e319d431145750b8207484e08", operation)
        self.assertRegex(operation, re.compile(r"(?m)^\s*& pwsh .* -Apply$"))

    def test_full_diagnostic_atomic_replace_has_explicit_backup(self):
        installer = (ROOT / "hostops/setup/owner-full-diagnostics-maintenance-once.ps1").read_text()
        self.assertEqual(installer.count("[IO.File]::Replace("), 2)
        self.assertNotIn("[IO.File]::Replace($next, $target, $null)", installer)
        self.assertNotIn("[IO.File]::Replace($restore, $target, $null)", installer)
        self.assertIn("[IO.File]::Replace($next, $target, $atomicBackup)", installer)
        self.assertIn("[IO.File]::Replace($restore, $target, $failedReplacementBackup)", installer)

    def test_title_alias_installer_preflight_and_crash_recovery(self):
        installer = (ROOT / "hostops/laptop-ops/operations/owner-title-alias-178-install.ps1").read_text()
        self.assertIn("TestStagedImports\n    if ($PreflightOnly)", installer)
        self.assertLess(installer.index("    TestStagedImports\n"),
                        installer.index("        StopOwner\n"))
        self.assertLess(installer.index("Ledger 'BACKUP_VERIFIED'"),
                        installer.index("        StopOwner\n"))
        self.assertIn("-I -B -c $python $stage", installer)
        self.assertIn("STAGED_IMPORT_FAILED_OWNER_UNCHANGED", installer)
        self.assertIn("param([switch]$PreflightOnly)", installer)
        self.assertIn("OWNER_TITLE178=PREFLIGHT_PASS_NO_OWNER_STOP", installer)
        self.assertLess(installer.index("    if ($PreflightOnly) {"),
                        installer.index("        StopOwner\n"))
        self.assertIn("Ledger 'SWAP_INTENT' $name", installer)
        self.assertLess(installer.index("Ledger 'SWAP_INTENT' $name"),
                        installer.index("[IO.File]::Replace($next,$target"))
        self.assertIn("'TTV-OWNER-TITLE178-RECOVERY-V2'", installer)
        self.assertIn("NoInFlightWork", installer)
        self.assertIn("function QuiesceForRollback", installer)
        rollback = installer.split("function QuiesceForRollback", 1)[1].split(
            "\n$identity =", 1)[0]
        self.assertNotIn("StopOwner", rollback)
        self.assertNotIn("NoOpenWork", rollback)
        self.assertIn("ROLLBACK_NEW_OWNER_WORKER_UNCERTAIN", installer)
        self.assertIn("ROLLBACK_TASK_RUNNING_OR_UNCERTAIN", installer)
        self.assertIn("HEALTH_REASON_", installer)
        self.assertIn("$identity.ReturnValue -eq 0 -and $identity.Sid -ceq $ownerSid", installer)
        self.assertNotIn("$identity.ReturnValue -eq 0 -and $identity.Sid -cne $ownerSid", installer)
        self.assertIn("LOADED_MODULE_PROVENANCE_NOT_INSTRUMENTED", installer)
        self.assertNotIn("Remove-Item -LiteralPath $backup", installer)

    def test_maintenance_timeout_covers_bounded_rollback(self):
        dispatcher = (ROOT / "hostops/jobs/owner-laptop-ops-dispatch.ps1").read_text()
        self.assertIn("$manifest.category -ceq 'owner-maintenance'", dispatcher)
        self.assertIn("{ 600 } else { 200 }", dispatcher)
        self.assertIn("-lt $waitSeconds", dispatcher)
        self.assertIn("HOSTOPS_OWNER_OPS_TIMEOUT_UNKNOWN_EFFECT_NO_RETRY", dispatcher)

    def test_title178_postinstall_diagnostic_is_read_only(self):
        diagnostic = (ROOT / "hostops/laptop-ops/operations/owner-title178-diagnostic.ps1").read_text()
        self.assertIn("acd823cb5d8898d237749b4ced5af8700953c1ab", diagnostic)
        self.assertIn("TTV-OWNER-TITLE178-DIAG-V4", diagnostic)
        self.assertIn("HEALTH_REASON_", diagnostic)
        self.assertIn("Get-FileHash -LiteralPath", diagnostic)
        self.assertNotIn("Stop-ScheduledTask", diagnostic)
        self.assertNotIn("Disable-ScheduledTask", diagnostic)
        self.assertNotIn("[IO.File]::Replace", diagnostic)
        self.assertNotIn("Remove-Item", diagnostic)

    def test_owner_source_trace_is_bounded_read_only(self):
        operation = (ROOT / "hostops/laptop-ops/operations/owner-p2-source-trace-readonly.ps1").read_text()
        dispatcher = (ROOT / "hostops/jobs/owner-laptop-ops-dispatch.ps1").read_text()
        self.assertIn("TTV-OWNER-SOURCE-TRACE-V1", operation)
        self.assertIn("262144L", operation)
        self.assertIn("OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'", operation)
        self.assertIn("AUTO_SOURCE_ROUTE=", operation)
        self.assertIn("AUTO_SUBTITLE_CACHED=YES", operation)
        self.assertNotIn("Invoke-WebRequest", operation)
        self.assertNotIn("Stop-ScheduledTask", operation)
        self.assertNotIn("Disable-ScheduledTask", operation)
        self.assertNotIn("[IO.File]::Replace", operation)
        self.assertNotIn("Remove-Item", operation)
        self.assertIn("$receipt.operation -ceq 'owner-p2-source-trace-readonly'", dispatcher)
        self.assertIn("HOSTOPS_OWNER_SOURCE_CACHED=", dispatcher)

    def test_batch_0011_quarantine_is_exact_and_preservation_first(self):
        operation = (ROOT / "hostops/laptop-ops/operations/owner-p2-b11-quarantine.ps1").read_text()
        self.assertIn("$expectedBatch = 'batch-0011'", operation)
        self.assertIn("40f98035778158467cce7b8e2016166763a3f5085381c0b90e2349e19f7252c5", operation)
        self.assertIn("P2_RECONCILE_INSTALLED_NO_RETRY_WORKER_MATCH", operation)
        self.assertIn("P2_RECONCILE_CHECKPOINT_PRESENT", operation)
        self.assertIn("P2_RECONCILE_PENDING_EVENTS", operation)
        self.assertIn("-ApplyQuarantine", operation)
        self.assertIn("-AcknowledgeUnknownEffect", operation)
        self.assertIn("P2_RECONCILE_ORIGINAL_MARKER_BYTES=PRESERVED", operation)
        self.assertNotIn("Start-ScheduledTask", operation)
        self.assertNotIn("Invoke-RestMethod", operation)
        self.assertNotIn("generateContent", operation)

    def test_406_installer_requires_exact_quarantine_and_atomic_backup(self):
        operation = (ROOT / "hostops/laptop-ops/operations/owner-opensub-406-install.ps1").read_text()
        self.assertIn("AssertQuarantinedB11", operation)
        self.assertIn("'UNKNOWN_EFFECT_NO_RETRY'", operation)
        self.assertIn("'Disabled'", operation)
        self.assertIn("[IO.File]::Replace($next, $target, (Join-Path $backup ('atomic-' + $name)))", operation)
        self.assertIn("'SOURCE_HASH_MISMATCH'", operation)
        self.assertIn("'INSTALLED_SOURCE_DRIFT'", operation)
        self.assertIn("'OFFLINE_IMPORT_FAILED'", operation)
        self.assertIn("StartOwner $oldPid", operation)
        self.assertNotIn("-ApplyQuarantine", operation)

    def test_en406_marker_recovery_is_single_target_and_no_provider(self):
        script = (ROOT / "hostops/laptop-ops/operations/owner-en-once-406-quarantine.ps1").read_text()
        self.assertIn("'MARKER_NOT_UNIQUE'", script)
        self.assertIn("OWNER_EN406_PREFLIGHT=ONE_ACTIVE_MARKER_ONE_RECENT_BLOCKED_EN_FAILURE", script)
        self.assertIn("OWNER_BRIDGE_BLOCK_REASON=EN_DOWNLOAD_ALREADY_ATTEMPTED", script)
        self.assertIn("CURRENT_AI_EN_ALREADY_CACHED", script)
        self.assertIn("CURRENT_LEGACY_EN_ALREADY_CACHED", script)
        self.assertIn("IdleP2", script)
        self.assertIn("Move-Item -LiteralPath $marker.FullName", script)
        self.assertIn("Hash $quarantine", script)
        self.assertIn("StartOwner $oldPid", script)
        self.assertNotIn("Invoke-WebRequest", script)
        self.assertNotIn("Invoke-RestMethod", script)
        self.assertNotIn("Remove-Item", script)
        self.assertNotIn("download_manual_en", script)

    def test_en406_recovery_diagnostic_only_classifies_private_logs(self):
        operation = (ROOT / "hostops/laptop-ops/operations/owner-en406-recovery-diagnostic.ps1").read_text()
        dispatcher = (ROOT / "hostops/jobs/owner-laptop-ops-dispatch.ps1").read_text()
        self.assertIn("4611cbb481f2b706c164238764f5509ecfcb9310", operation)
        self.assertIn("3f070231a90039185b85e5963b0a575d1f39e0c8", operation)
        self.assertIn("full-owner-output.log", operation)
        self.assertIn("TTV-OWNER-EN406-RECOVERY-DIAG-V1", operation)
        self.assertIn("HOSTOPS_EN406_DIAG_QUARANTINE=", dispatcher)
        self.assertIn("HOSTOPS_EN406_DIAG_MARKER=", dispatcher)
        self.assertIn("$summary.nonce -ceq $nonce", dispatcher)
        for forbidden in ("Start-ScheduledTask", "Stop-ScheduledTask", "Disable-ScheduledTask",
                          "Enable-ScheduledTask", "Invoke-WebRequest", "Invoke-RestMethod",
                          "Remove-Item", "Move-Item -LiteralPath $marker"):
            self.assertNotIn(forbidden, operation)

    def test_en406_ready_resume_only_starts_idle_verified_owner(self):
        script = (ROOT / "hostops/laptop-ops/operations/owner-en406-ready-resume.ps1").read_text()
        self.assertIn("OWNER_EN406_RESUME=PREFLIGHT_READY_IDLE_HASH_VERIFIED", script)
        self.assertIn("OWNER_EN406_RESUME=FRESH_OWNER_RUNNING", script)
        self.assertIn("'OWNER_TASK_NOT_READY'", script)
        self.assertIn("'P2_ACTIVE_OR_UNKNOWN'", script)
        self.assertIn("'INSTALLED_MODULE_HASH_DRIFT'", script)
        self.assertIn("GetOwnerTask", script)
        self.assertIn("GetOwnerSid", script)
        self.assertIn("Start-ScheduledTask", script)
        self.assertNotIn("Disable-ScheduledTask", script)
        self.assertNotIn("Enable-ScheduledTask", script)
        self.assertNotIn("Stop-ScheduledTask", script)
        self.assertNotIn("Stop-Process", script)
        self.assertNotIn("Remove-Item", script)
        self.assertNotIn("Move-Item", script)
        self.assertNotIn("Invoke-WebRequest", script)
        self.assertNotIn("Invoke-RestMethod", script)


if __name__ == "__main__":
    unittest.main()
