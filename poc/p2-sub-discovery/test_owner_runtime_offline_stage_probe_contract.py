"""No Owner account, TV, real data, network or provider access in this test."""
from pathlib import Path
import re
import unittest

SCRIPT = (Path(__file__).resolve().parents[2] /
          "hostops/setup/owner-runtime-offline-stage-probe.ps1")


class RuntimeOfflineStageProbeContract(unittest.TestCase):
    def setUp(self):
        self.text = SCRIPT.read_text(encoding="utf-8")

    def test_owner_only_and_existing_receipt(self):
        for item in ("TTV_RUNTIME_PROBE_VERSION=V3_OFFLINE_STAGES",
                     "TTV_RUNTIME_HEALTH=", "TTV_RUNTIME_FLOW_INIT=",
                     "TTV_RUNTIME_TASK_LAST_RESULT=", "OWNER-AGENT-HEALTH-V1",
                     "HOLD_INTERACTIVE_OWNER_REQUIRED",
                     "TorrentTV-Vietsub-OwnerAgent"):
            self.assertIn(item, self.text)

    def test_no_network_or_disk_mutation(self):
        for item in ("-B -c $smoke", "socket.socket.bind = no_transport",
                     "socket.socket.listen = no_transport",
                     "socket.socket.connect = no_transport",
                     "urllib.request.build_opener = no_transport",
                     "OPENSUBTITLES_API_KEY", "PLACEHOLDER_NOT_A_CREDENTIAL"):
            self.assertIn(item, self.text)
        for forbidden in ("Start-ScheduledTask", "Stop-ScheduledTask",
                          "Set-ScheduledTask", "Register-ScheduledTask",
                          "Invoke-WebRequest", "Invoke-RestMethod",
                          "Start-Process", "Set-Content", "Out-File"):
            self.assertIsNone(re.search(r"(?m)^\s*" + forbidden + r"\b",
                                        self.text))

    def test_flow_import_profile_init_are_distinct(self):
        for item in ("IMPORT_FAILED", "PROFILE_FAILED", "INIT_FAILED",
                     "STAGE_PASS_LIVE_RUNTIME_UNVERIFIED",
                     "HOLD_FLOW_INITIALIZATION"):
            self.assertIn(item, self.text)
        self.assertNotIn("SecureStringToBSTR", self.text)
        self.assertNotIn("print(Exception", self.text)


if __name__ == "__main__":
    unittest.main()
