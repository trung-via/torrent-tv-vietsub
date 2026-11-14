# P3 owner-private restart-durable replay ledger (SQLite, SOURCE_ONLY)

**Decision:** User approved continuing after Redmi current-status [Draft #154](https://github.com/trung-via/torrent-tv-vietsub/pull/154) and native Android [Draft #155](https://github.com/trung-via/torrent-tv-vietsub/pull/155). Original issue [#149](https://github.com/trung-via/torrent-tv-vietsub/issues/149). This PR is a single child of #154, leaves #155 and LEAN120/D1/D2/P4 entirely unchanged.

## Threat and contract

Previously `SignedRedmiStateCache` held `boot_id`, increasing sequence and nonces only in RAM, and `SignedPlaybackVerifier` held the Play/Next/Close nonces only in RAM. If the owner-agent restarted, a previously signed but still time-valid packet might pass those memory guards. A cryptographically authenticated Play packet must never alone establish that the TV remains on that item: a **separately fresh TV state (<=8s, ON, active)** and exact owner-local TorrServer metadata remain mandatory.

`p3_owner_replay_journal.OwnerReplayJournal` stores **only**:
- one latest Android `boot_id`, last TV status `sequence`, owner UTC receipt millisecond (no TV session/movie/file ID);
- retired boot identifiers to forbid resurrection of old Android process sessions;
- bounded recent nonces for separate status and Play/Next/Close domains;
- latest selection sent timestamp for basic out-of-order filtering.

No certificate/key, media hash, server profile, filename, subtitle, user identifiers or session tokens are stored. The owner-only SQLite database lives under an explicit absolute private owner root as `p3-replay/ledger.sqlite3`; on POSIX its directory is mode 0700 and file 0600. **Windows ACL evaluation is still a local deployment gate**: file mode alone is not a Windows ACL guarantee. Reject root/journal symlinks and unavailable/corrupted DB. SQLite uses `BEGIN IMMEDIATE`, unique nonce index, `synchronous=FULL`, transaction commit before publishing accepted state/selection. No sleep/retry queue and never silently fall back to RAM if a durable write fails.

The mandatory existing owner composition `compose_owner_redmi_status` now installs **the same** journal for both `SignedRedmiStateCache` and `SignedPlaybackVerifier`. The old constructors retain optional injection for pure unit-test compatibility, but production composition does not offer a memory-only path.

### Restart semantics

On owner PC restart, the database retains high-water values and nonces but **never rehydrates a fresh/active TV status**. Before a new independent signed Redmi status, the owner state reader returns HOLD and no provider call may occur. Same Android `boot_id` must increase `sequence`. A changed Android `boot_id` cannot take over a still-fresh prior boot (up to 8 seconds by persisted PC UTC receipt time); older boot IDs are retired and refused. Each selection packet's nonce is also deduplicated across owner restarts; its signed `sent_at_ms` remains bounded by the existing ±15s HMAC verification.

Authenticated signatures must be checked **before** touching the journal; invalid packets cannot poison its high-water. On DB corruption/lock, fail CLOSED; do not delete or recreate the journal automatically, no replaying a pending quota-bearing provider POST. Synthetic tests include same packet replay after a new Python object, new strictly increasing state, old boot resurrection, tamper attempts, signed selection replay, corrupt SQLite, simultaneous competing transactions and schema privacy.

### Limits

This is a **source candidate**, not an installed owner Windows service. An end-to-end durable guarantee still depends on a private, trusted and stable owner root and correct Windows ACL, single-device pairing-key isolation, disk durability and actual runtime lifecycle. A time-valid packet not yet received by Windows before a crash cannot be inferred as previously acted upon; the existing owner private V3 no-auto-retry claim is an independent quota safety guard. A user with privileged write access to the private journal or pairing secret is outside the guarantee.

TV signed heartbeat and native Debug APK are in #155; it still must be installed/paired separately. This PR **does not open a LAN socket, change firewall, install/start Task Scheduler, change P4 consent, release APK, or send any content to Gemini/OpenSubtitles**. Repository is PUBLIC; all tests and examples are synthetic. Retain Draft/HOLD until independent Brain PASS (Issue #42), relevant CI and real Redmi/owner acceptance.
