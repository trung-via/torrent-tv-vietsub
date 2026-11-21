# One-pass P3 → P2 → P4 → G2 audit (2026-11-21)

Scope: one existing OMP/Redmi player, one Windows Owner, one selected TorrServer
file, one viewer press, the existing D1/D2/LEAN120 translator and signed P4
receiver. This is **source plus bounded read-only diagnostics**, not a claim
of a newly installed APK, live provider completion or on-screen subtitles.

## Stage-by-stage evidence contract

| Stage | Current proof / source gate | Observable V4 or TV event | Still needed for real PASS |
| --- | --- | --- | --- |
| OMP G1/VLC actual item | Native `session.load` / accepted next item; no pause/seek redispatch | P3 signed 3s state, `P3_SELECTION_ACCEPTED` | Same physical Redmi/current item verified |
| One viewer request | `Bật Vietsub AI` signs REQUESTED; OFF/OTHER cancels | `P3_SELECTION_ACCEPTED DISPATCH`, not duplicate SKIP | TV identity and real button observation |
| Owner/TorrServer current file | V3 checks current session and selected-file metadata; returns distinct P3 reject classes | `p3_state`, P3 ingress counters | Real localhost selected-file identity, not TCP alone |
| VI-first and local/EN source | Existing D1/D2 and owner-local cache; at most one authorized selected download | Owner-private cache index; `EN_INDEX_NOT_READY` if absent | VI/EN receipt verified, actual rights/provider facts |
| P2 paid LEAN120 | Existing single checkpointed worker, no replay of uncertain batch; R2 per-session callback | `p2.batch`, `committed_prefix`, marker age, final flag | Whole-film final and paid model receipt; no assumed success from STARTED |
| Rolling P4 source | Rehydrate only validated contiguous checkpoints, even if callback missed; do not run worker in GET/activate | `P4_ROLLING_STATUS`: flow/index/key/pending/ready | Exact live TV↔Owner `mediaKey` and earliest 120-cue checkpoint |
| P4 `/p4/activate` | Existing private TLS/HMAC and current media gate | activate OK/rejected, source-not-accepted counts | Authenticated session established on TV |
| P4 `/p4/revision` | Existing signed feed 200/204 / source HOLD | revision-ready, empty, hold counts | First 120→240→final actual frame sequence |
| OMP G1/G2 refresh | Existing native P4 signed receiver and persisted first-frame ACK | Android `P4_TV_OFFER_RECEIVED_UNVERIFIED`, `P4_TV_G2_FIRST_FRAME_ACK` | VLC really shows cue 131+, pause/seek/audio preserved, no picker |
| OFF, OTHER, film switch | Existing no-replay and per-media gates | Cancellation; no subsequent revision accepted | Real A→B→A/OFF/OTHER smoke |

## Source defects addressed together

1. **Lost P3 status clock:** original `p3StatusTick` returned permanently when
   the sharing preference was OFF at player load. The one-tap button enabled
   it later but the three-second signed-state clock had already stopped.
   Owner TV freshness expires after eight seconds, before the next 15-second
   P4 activation retry. The tick now survives OFF without network sampling,
   and samples as soon as the viewer enables the feature mid-playback.
2. **P4 403 lacked a discriminating cause:** R2 checkpoint lookup could fail
   because the flow was unbound, native TV media key differed, EN source index
   was not prepared or no checkpoint was yet committed. V4 emits fixed Owner-
   private status enums, and preserves the specific cause instead of replacing
   it with a generic feed-missing event. None of these statuses contains a
   media key, path, subtitle, session ID or film name.
3. **`P2_STARTED` was treated as near completion:** V4 exposes contiguous
   checkpoint count and active in-flight age independently of the historical
   conservative `UNKNOWN_EFFECT_HOLD` state. A marker for batch N while the
   Owner advances is *in-progress*, not evidence to clear/replay/delete it.
4. **No end-to-end receipt:** an Owner-only bounded tail of the existing full
   diagnostic log is reduced to P3 dispatch, P4 activation, signed revision,
   hold and source rejection counters. The 4 KiB ProgramData receipt goes to
   the already enrolled HostOps reader, never raw Owner log lines. Long-running
   Owners retain tail observation only when writer PID matches live health.
5. **TV side was opaque:** native Android logs record activation-pending,
   accepted session, unverified offer and the persisted G2 first-frame ACK as
   distinct fixed stage markers, with no secret or subtitle content.

## Interpretation and non-claims

- A P3 `DISPATCH` proves the Owner accepted a viewer request, **not** provider
  result, P4 session or rendered subtitle.
- `AUTO_EN_TO_P2=STARTED` proves worker entry only. A moving
  `batch-0004` → `batch-0010` is positive progress but not `vi-final`.
- `P4_ACTIVATE_REJECTED_P3_READY_NO_CURRENT_ACCEPTED_SOURCE` can occur while
  a checkpoint is pending, because of media-key drift, or because source
  activation is not ready; only the adjacent V4 rolling reason can separate
  these. A 403 by itself is insufficient for a destructive P2 reset.
- HTTP 200 activation is not a 200 revision. A 200 revision is not a native
  G2 first-frame acknowledgment. A G2 ACK still needs visible cue QA.
- Historical blocked P2 claims are preserved. This patch does **not** reset
  in-flight P2, reinstall Owner or force a new paid request.

## Rollout order (no interruption of a paid film)

1. Publish and pass exact-head source/Windows PowerShell 7/Android composed
   debug CI. **Source tests are not deployment receipts.**
2. Upgrade the read-only trusted HostOps V4 consumer on its exact pinned
   branch/commit **before** any Owner writer begins sending schema V4.
3. Verify Owner task identity/hash and that `pending_events=0` and
   `inflight_count=0`, with no active translator; only then stage the exact
   owner-source bytes and perform a bounded controlled Owner restart.
4. Build the exact pinned OMP debug APK; verify signer, package, ABI, install
   without uninstall/data wipe and read back the APK SHA. The historical P4
   debug-install GitHub workflow is intentionally disarmed; source commit or
   CI does **not** authorize assuming its execution.
5. On the actual Redmi, one user press must yield at least 120, then 240
   cumulative cues, a persisted G2 first-frame ACK, visible correct text,
   and OFF/OTHER/film-switch refusal. Record installed SHA and observer.

## Test matrix

- `poc/p2-sub-discovery`: 513 unit tests, one skipped, offline PASS.
- `poc/p4-auto-sub`: 24 Python patcher/source contract tests PASS.
- Windows PowerShell 7 parser, Gradle/Android assemble, true HostOps V4 read,
  Android `adb logcat`, actual P4 LAN/Redmi render: **not established by these
  local tests**. Each requires separate exact-head/live evidence.

Roll back by reverting the source overlays and retaining the pre-upgrade
Owner snapshot and APK; do not alter a running P2 claim or any user data.
