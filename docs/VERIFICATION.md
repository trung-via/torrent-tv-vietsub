# Verification contract

Layer A (no external hardware): static analysis, Kotlin unit tests, mocked HTTP API, app build and emulator focus tests where supported. Layer B: live TorrServer LAN health + legal fixture/seek test when endpoint & permission available. Layer C: physical TV install/navigation/playback/subtitles when TV, ADB and permission available.

Report each layer independently: `NOT_RUN`, `PASS`, `FAIL`, `BLOCKED`, `UNVERIFIED`. No default PASS for absent hardware. Do not invoke full AIOS-renew test suite for unrelated app modifications. Review scope according to verified AIOS canonical governance at dispatch time; preserve evidence and do not silently retry until green.
