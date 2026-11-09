# P2-AISUB R3.1 → R3.2: private-source discovery gate

**Scope:** inventory only; no Antigravity invocation, translation, old checkpoint access, Windows file writes, installation, source extraction, full-disk search, model retry, G4 or TV action.

**Context:** merged `main=a72b1f8a0b07d36b311752b8ccd9840a5683c904` contains the isolated R3.2 scheduler `poc/p2-aisub/r3_2_continuous_queue.py`, with CI 255/255 PASS (run #42685509528). The previous R3.1 helper was generated as `Torrent_TV_AISUB_R3_1_WorkLock_Telemetry.zip` in an older private ChatGPT conversation, but those original bytes and their installed Windows workdir have **not been recovered in the current session**. Prior R3.1 offline 13/13 PASS does not establish a real Windows installation.

`hostops/jobs/r31-private-inventory.ps1` runs only through Issue #82's existing owner-command inbox on independent `torrent-tv-vietsub-win`. Checks only exact known package or direct Python script **basenames** in the runner account's `Downloads`, `Desktop` and `Documents` (three folders); no wildcard, recursive scan, paths printed, file writes or contents of user SRT/JSON/checkpoints. If a ZIP exists with a bounded size, it inspects only its ZIP central-directory **entry names**, not contents. The result must remain scoped to the runner account: it cannot prove source absence from other accounts, nested folders or unmounted previous ChatGPT artifacts.

**Report evidence:**
- `R31_PRIVATE_ZIP=EXPECTED_R31_CODE_NAMES_PRESENT_NO_CONTENT_READ` means source package may be available for a separate, privately authorized exact-SHA inspection. It does not establish the current installed R3.1 version, Work Owner lock or scheduler API compatibility.
- `R31_PRIVATE_SOURCE=NOT_FOUND_IN_CHECKED_LOCATIONS` means **only** that the limited exact-name probes saw no source; do not recreate or overwrite R3.1.
- `R31_PRIVATE_SOURCE_SHA=NOT_VERIFIED`, `R31_WORK_OWNER_OS_LOCK=NOT_OPENED`, `R31_CHECKPOINTS_AND_TRANSLATED_SRT=NOT_READ_OR_CHANGED` and `R31_PRIVATE_R32_INTEGRATION=NOT_RUN` remain the truth regardless of inventory outcome.

**Next gate:** obtain exact private R3.1 files and SHA in an authorized private context, reconcile active process and existing checkpoint/source manifest, implement and offline-test a source-specific adapter with the actual OS lock, and first prove all-cached/no-provider resume. Live Gemini 3.8 Flash High and timing acceptance are later distinct approvals and measurements.

Repository PUBLIC: do not paste private code, copyrighted English/Vietnamese subtitle lines, real local paths, account names or model credentials into PR/comments/logs.
