"""Static contract for the owner-local offline startup root-cause probe.

No Windows Owner credentials, Task Scheduler, TLS, sockets or real media are
accessed by this test. The actual script is separately parsed on Windows.
"""
from pathlib import Path
import re
import unittest


SCRIPT = (Path(__file__).resolve().parents[2] /
          "hostops/setup/owner-startup-offline-rootcause-probe.ps1")


class OfflineOwnerStartupProbeContract(unittest.TestCase):
    def setUp(self):
        self.text = SCRIPT.read_text(encoding="utf-8")

    def test_exact_owner_context_and_task(self):
        self.assertIn("TorrentTV-Vietsub-OwnerAgent", self.text)
        self.assertIn("S-1-5-20", self.text)
        self.assertIn("GITHUB_ACTIONS", self.text)
        self.assertIn("TTV_STARTUP_TASK_OWNER=MATCH", self.text)
        self.assertIn("start-owner-session-agent.ps1", self.text)

    def test_private_owner_read_only_checks(self):
        for item in ("TTV_STARTUP_LAUNCHER_PARSE=PASS",
                     "TTV_STARTUP_DPAPI=UNSEAL_PASS",
                     "TTV_STARTUP_DPAPI=UNSEAL_FAIL",
                     "TTV_STARTUP_BIND_IP=",
                     "TTV_STARTUP_BIND_PORT=",
                     "TTV_STARTUP_PYTHON=PASS",
                     "TTV_STARTUP_TLS=LOAD_PASS",
                     "TTV_STARTUP_TLS=LOAD_FAIL",
                     "TTV_STARTUP_PROBE_RESULT=READ_ONLY_PASS_RUNTIME_UNVERIFIED"):
            with self.subTest(item=item):
                self.assertIn(item, self.text)
        self.assertIn("ConvertTo-SecureString", self.text)
        self.assertNotIn("SecureStringToBSTR", self.text)
        self.assertNotIn("PtrToStringBSTR", self.text)
        self.assertIn("ctx.load_cert_chain", self.text)

    def test_no_mutation_or_external_transport(self):
        for forbidden in ("Start-ScheduledTask", "Stop-ScheduledTask",
                          "Enable-ScheduledTask", "Disable-ScheduledTask",
                          "Register-ScheduledTask", "Set-ScheduledTask",
                          "Invoke-RestMethod", "Invoke-WebRequest",
                          "TcpListener", "Start-Process", "Out-File",
                          "Set-Content", "Set-Item", "Remove-Item"):
            with self.subTest(forbidden=forbidden):
                self.assertIsNone(re.search(r"(?m)^\s*" + forbidden + r"\b", self.text))

    def test_no_raw_exception_or_private_values_in_report(self):
        for forbidden in ("Write-Host $_", "Write-Output $_",
                          "Write-Host $bindIp", "Write-Host $bindPort",
                          "Write-Host $encrypted", "Write-Host $secret"):
            self.assertNotIn(forbidden, self.text)
        for line in self.text.splitlines():
            if re.match(r"\s*Write-Host\b", line):
                self.assertNotIn("Exception.Message", line)
                self.assertNotIn("Get-Content", line)


if __name__ == "__main__":
    unittest.main()
