# P3/P4 owner-runtime integration — source candidate (2026-11-14)

## Authority and state

- Repository: `trung-via/torrent-tv-vietsub` (PUBLIC); integrated Draft [PR #162](https://github.com/trung-via/torrent-tv-vietsub/pull/162), based on `main@ad853ebd5acd` at this checkpoint.
- User-selected OMP movie **identification (Play/Next) is NOT translation authorization**. The on-TV explicit per-film **Bật Vietsub AI** signed event and fresh separately signed REQUESTED status are both required before any source search or paid work. OFF/OTHER and A→B→A invalidate the source.
- Reuse the original D1/D2 OpenSubtitles route, local VI/EN and one Gemini 4 Hydrogen HIGH LEAN120 worker, then existing ready-source P4 signed feed and native G1/G2 receiver; never add a second translator, queue, subtitle renderer or LAN service.
- GitHub [Issue #42](https://github.com/trung-via/torrent-tv-vietsub/issues/42) requires independent Brain PASS on exact current HEAD/base and applicable acceptance before GitHub merge. No merge, Windows installation, API upload/charge or TV deployment from this document.

## Source integration delivered in PR #162

`poc/p2-sub-discovery/owner_p3_p4_runtime.py` is an **opt-in callable** for a single authenticated HTTPS gateway and the existing owner agent. It consumes the already-typed `OwnerP3StatusComposition` produced by `compose_owner_redmi_status()`. That composition contains:

- Signed TV current-state cache + durable anti-replay journal;
- real `OwnerTorrServerReader` for the owner-pinned localhost-only TorrServer selected-file metadata (no TV JSON-controlled endpoint);
- independently supplied owner-local **authorization**, **rights**, **verified VI-track inventory**, and **exact pinned local file** callbacks;
- original `VerifiedV3Processor`, `P3OwnerReadyRegistry`, `PairedActivation`, and shared P3+P4 HTTPS handler.

`run_owner_p3_p4_runtime()` passes the composition's **existing** `trusted_v3_factory` into `run_owner_agent()` and serves the **same** composed `/p3/state`, `/p3/selection`, `/p4/activate`, `/p4/revision/...` handler. It performs no work on module import. A call is refused unless all of the following hold: explicit `explicit_start_lan=True`, Windows interactive session (not Session0/CI), owner-root paths, owner-root-contained PEM cert/key, configured RFC1918 literal IP, port ≥1024, TLS ≥1.2 and a verified-ready P4 composition. It cleans up the listener when the owner agent exits, without reinstalling services or changing Windows Firewall.

**This entrypoint is not auto-invoked by the older installed `start-owner-session-agent.ps1`.** It is a reviewed integration seam for a future owner-authorized interactive launcher. Do not advertise it as a currently running gateway or a completed deployment. The installed owner task/source version, actual P4 pairing secret and approved callback sources must be validated locally before any activation.

## Trust gates that cannot be guessed or bypassed

1. **Owner callbacks are NOT optional policy defaults.** Never implement `owner_auto_allowed=lambda: True`, `media_rights_allowed=lambda *_: True`, or `verified_local_vi_state=lambda *_: "ABSENT"` in production. These appear ONLY in synthetic unit fixtures. A missing, stale or ambiguous source/track inventory must HOLD, not trigger OpenSubtitles/Gemini.
2. **HTTPS certificate, pairing key and owner files remain private.** Existing Android pinned leaf cert/IP-SAN, P4 device secret and exact TV session must match; a generated test certificate or bool `attested=True` is not proof. Neither GitHub runner nor PUBLIC CI may read them.
3. **No duplicate worker/charges:** original V3 result alone registers VI or completed EN→VI. P4 activation reads only that validated final file; current #160/#162 sends one final VI revision, **not yet** live progressive 120→240 cue-131.
4. **Existing Windows owner process installation** is an earlier pinned copy with DPAPI and a Task Scheduler entry; source code edits and synthetic CI do NOT upgrade it. The runner is NETWORK_SERVICE Session0, not the owner's desktop.
5. **Safety and real-world acceptance:** complete actual owner-local TLS/DPAPI/policy/inventory/selected-file wiring with authorization, exact Android APK provenance, paired private LAN, no-picker video cue 131, OFF/OTHER, VLC seek/pause/audio, stale session and A→B→A on Redmi A Pro 55. Real OpenSubtitles and Gemini API requests require their own provider/auth/source-consent evidence; G4 Release is separate.

## Test evidence and next handoff

- Previous integrated Android Debug [run #43591382160](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/43591382160) succeeded at `d114c47b58a4`: `assembleDebug`, `testDebugUnitTest` and private debug APK SHA. This was before the new source-only runtime module; never treat that old run as proof of a newer source head.
- Source checks live in `test_owner_p3_p4_runtime.py`: no import-time listener/provider, one composed handler, RFC1918/TLS guard, listener shutdown on agent exit and CI/no-explicit-start refusal. All fixtures synthetic. Cross-lane and D1/D2 CI on current PR HEAD should be checked independently.
- Next step: a **separately authorized owner-session deployment/real LAN test** (not GitHub runner or untrusted PR runner), where the caller supplies owner-pinned TV pairing, TorrServer, policy and verified local VI inventory. Without that, state stays `OWNER_RUNTIME_SOURCE_ONLY / LIVE_LAN_NOT_RUN / REAL_TV_AUTO_NOT_RUN / MERGE_HOLD`.

The approved roadmap target is unchanged: authorized matching VI, otherwise trusted EN→existing LEAN120, then original signed P4 feed to native OMP on the exact current Redmi session.
