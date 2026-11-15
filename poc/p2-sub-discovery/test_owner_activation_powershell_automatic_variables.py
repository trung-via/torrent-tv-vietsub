"""Regression: PowerShell automatic variables are case insensitive.

A real Windows owner activation failed after a successful PR SHA check because
$home was assigned as if it were local: HOME is PowerShell's read-only
automatic variable. Preserve the fault signature and cover the next installer
step. Source-only: no Windows task, filesystem writes or provider calls.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent
OWNER_SCRIPTS = (
    "activate-owner-p3-p4.ps1",
    "install-owner-session-bridge.ps1",
    "start-owner-session-agent.ps1",
)

# Unqualified assignments to these names collide with PowerShell automatic
# and invariant variables in a user session (PowerShell is case insensitive).
RESERVED = frozenset((
    "home", "host", "pid", "profile", "error", "true", "false", "null",
    "pwd", "psversiontable", "pscmdlet", "myinvocation", "executioncontext",
))
DIRECT_ASSIGN = re.compile(
    r"(?im)^\s*\$([a-z][a-z0-9_]*)\s*(?:\+\+|--|[+\-*/%]?=(?!=))"
)


class ProtectedAutomaticVariablesTests(unittest.TestCase):
    def test_no_direct_assignment_to_powershell_auto_variables(self):
        for name in OWNER_SCRIPTS:
            with self.subTest(source=name):
                source = (ROOT / name).read_text(encoding="utf-8")
                bad = []
                for line_num, line in enumerate(source.splitlines(), 1):
                    match = DIRECT_ASSIGN.match(line)
                    if match and match.group(1).lower() in RESERVED:
                        bad.append(f"{line_num}:{match.group(1)}")
                self.assertFalse(bad, "PowerShell read-only variables: " +
                                 ", ".join(bad))

    def test_installer_and_activation_use_non_reserved_bindings(self):
        activation = (ROOT / OWNER_SCRIPTS[0]).read_text(encoding="utf-8")
        installer = (ROOT / OWNER_SCRIPTS[1]).read_text(encoding="utf-8")
        self.assertIn("$ttvLocalAppRoot = Join-Path $env:LOCALAPPDATA",
                      activation)
        self.assertIn("$translatorProfileConfig = Get-Content", installer)
        self.assertNotRegex(activation, r"(?i)\$home\b")
        self.assertNotRegex(installer, r"(?i)\$profile\b")


if __name__ == "__main__":
    unittest.main()
