# P1a / G1d — Subtitle error UX decision draft

**Status:** PROPOSED_UX / SOURCE_AUDITED / IMPLEMENTATION_NOT_STARTED / UX_REAL_TV_UNVERIFIED  
**Date:** 2026-10-26  
**Authority:** docs/PROJECT_CONTRACT.md C0/C1.6/C1.7/C6, docs/PRD.md sections 3/5, planning/P1A-ACCEPTANCE-CRITERIA-20261025.md AC-06, Draft PR #27.
**No approval implied:** This file is a proposal, not a Human product decision, contract change, app patch, AIOS task, merge, release or AC06_PASS.

## 1. Evidence: safe failure vs. useful user feedback

- HUMAN_PASS, real Redmi + VLC, existing SEL-01 ARM32 debug APK: five independently guarded negative SRT cases — missing file (PR #23), malformed UTF-8 (#24), malformed syntax (#25), syntactically valid but SHA256 changed (#26), file unreadable under app UID (#27). Each case had restored-file evidence. Source negative behavior and real-TV safety do not prove that the viewer understood the failure.
- SOURCE_VERIFIED at stacked commit ed4c71b01f744541bbea0a3196254bd55d4e2419: poc/g1c/P1G1CSubtitleRegistry.debug.kt validates regular file/read access/length, strict UTF-8/cue regex and per-media checksum. On missing/corrupt/changed/unreadable file it returns normal PlayRequest; catches IO/charset/security exceptions without creating subtitle-error UI. The release helper is currently a no-op, but G4 release artifact remains UNVERIFIED.
- SOURCE_VERIFIED from OMP upstream pin 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f: android/.../player/PlayerActivity.kt already has showMessage(text, error) and player_toast (normal message about 3 seconds). load() calls session.load(), then hideMessage() during reset: any new notice must be issued only **after** that reset, otherwise it will disappear immediately. NativePlayer.kt and PlayerSession.kt have existing message/notification channels; choose the smallest verified seam, not a new subsystem.
- AC-06 explicitly requires both safe playback when SRT is missing/invalid/unreadable and **appropriate error feedback**. Existing debug fail-closed tests cover safety but **NOT** the UX branch, therefore AC06_PARTIAL and AC06_UX_UNVERIFIED.

## 2. Alternatives requiring Human decision

| Option | Value | Consequence | Recommendation |
| --- | --- | --- | --- |
| A. Defer notification for debug PoC | No new build or device mutation | Silent G1c disappearance; AC06_PARTIAL must remain, and UX moved to future production importer | Allowed only with explicit Human deferral |
| B. Nonblocking, localized subtitle warning on exact saved track failure | Reuses OMP's existing player toast, no new service/backend, playback uninterrupted | Small debug Kotlin/PlayerActivity patch and new build + TV tests; G4 still separate | **PROPOSED / RECOMMENDED** |
| C. Blocking dialog or bespoke screen | Highly noticeable | Disrupts playback/D-pad and adds scope | Not recommended |

**Proposed Vietnamese copy for B:** “Phụ đề rời đã lưu không khả dụng. Kiểm tra file SRT.”

Do not claim file was deleted, permissions changed, or that a UI importer already exists. Keep cause-neutral language because the same UX covers different negative causes. No absolute file paths, media identity hashes, torrent URLs, credentials, trackers or tokens in UI/logs.

## 3. Exact trigger: suppress false alarms

Only emit one warning during a **new VLC playback of current registered item A** if all conditions hold:
1. Verified serverProfileId + torrent v1 infohash + fileIndex for the item being opened; no identity fallback from title, URL, filename, or source path.
2. Its SharedPreferences media association exists and its explicit selected state equals **on**; no G1c registration marker is pending. Previously choosing on is required: do not show a warning for unknown/unregistered media.
3. The currently saved SRT is missing, unreadable, malformed, or different digest so the G1c subtitle cannot be added. Distinguish this from unrelated native playback/network failures.

**Suppress** for unregistered B, saved off/other choice, built-in/2160 engine, embedded-only tracks, or uncertain profile/media identity. Do not repeat per frame/seek, and do not override subtitle selection, video/audio, focus or Back.

Candidate implementation uses a tiny typed preparation result (unchanged PlayRequest plus optional user-safe failure code), consumed inside PlayerActivity **after** load's hideMessage reset. No preferences mutation on errors; no full-scope exception details. Verify choice and current media on callback to avoid stale-item warnings.

## 4. Scope only if B is authorized

Allowed proposed files: poc/g1c/P1G1CSubtitleRegistry.debug.kt, poc/g1c/P1G1CSubtitleRegistry.release.kt (consistent no-op signature), poc/g1c/apply.ps1 and narrow verification/test additions under poc/g1c or poc/g1d. Modify the **disposable pinned upstream OMP checkout**, never silently edit production workspace. PlayerActivity.kt is touched only through the guarded narrow apply patch. Need verify the native localization path before code: OMP snapshot src/i18n contains en.ts/ru.ts, so no claim that the pinned player already has Vietnamese translation. No UI rewrite, new TS bridge, database, backend, Windows SMB/firewall/router, WAN or Android elevated privileges.

Acceptance and evidence:
- UX-01: saved ON registered A + missing SRT ⇒ exactly one comprehensible Vietnamese subtitle warning, G1c omitted, VLC AV and D-pad still work.
- UX-02: bad UTF-8, malformed syntax, content checksum mismatch and unreadable SRT ⇒ same safe warning, no crash/secret leak.
- UX-03: unregistered B and selected OFF/OTHER A, native built-in player ⇒ **no false positive** and no automatic ON.
- UX-04: restore original SRT, reopen VLC A ⇒ G1c Vietnamese cues return and no warning; preserve ON/OFF, A→B→A, pause/seek/resume.
- UX-05: source proof + targeted unit tests + authorized dedicated-runner debug APK with SHA256 + Human real-Redmi screen/remote observation. Source review alone, emulator or CI alone cannot mark REAL_TV_PASS.
- UX-06: no sensitive info or unintended preferences changes; no new service/network changes.
- G4: release binary debug-hook/asset/registry isolation separately verified, **UNVERIFIED** until that artifact is examined.

Stop if patch needs to change engine selection, introduces cross-episode notice, overrides OFF, logs sensitive data, requires root, changes app-private registry/markers unexpectedly, or lacks source/runner/test authorization. Rollback by dropping patch/branch in disposable clean tree, not by clearing TV app data.

## 5. Human decision needed before implementation

- **Choose B:** approve a separate minimal nonblocking subtitle-warning patch with exact-media/ON gating and renewed build + TV evidence.
- **Choose A:** defer notification until an importer/production UX is available, and explicitly keep AC06_PARTIAL / AC06_UX_UNVERIFIED.

Either choice leaves G4 release isolation UNVERIFIED and grants no permission to merge/publish or alter AIOS.
