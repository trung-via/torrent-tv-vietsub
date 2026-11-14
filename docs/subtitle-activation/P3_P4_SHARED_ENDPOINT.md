# P3 + P4 one owner-paired HTTPS listener — source integration

2026-11-14 · **SOURCE CANDIDATE**, no owner Windows listener/port/task started. Issue [#149](https://github.com/trung-via/torrent-tv-vietsub/issues/149), PC signer [#150](https://github.com/trung-via/torrent-tv-vietsub/pull/150), V3 exact identity [#148](https://github.com/trung-via/torrent-tv-vietsub/pull/148), TV sender sibling [#151](https://github.com/trung-via/torrent-tv-vietsub/pull/151).

## Why reuse P4 rather than start another LAN service?

`poc/p2-aisub/paired_activation.py` already defines `make_paired_handler(controller)` for `POST /p4/activate` and `GET /p4/revision/{session}`. `run_assumed_source_gateway.py` already explicitly creates an owner-only TLS server with a pinned IP-SAN leaf certificate and HMAC pairing secret; it is **not** a live auto-source/V3 server. Creating a separate listener for P3 would duplicate TLS/port/pairing and introduce additional Windows/firewall rights.

`p3_p4_shared_https_route.make_p3_p4_handler(p4_controller, p3_owner_adapter)` composes an **optional P3 route** into the existing paired handler; when constructed, it preserves the P4 GET/revision and POST/activate semantics. It must be created only by a separately owner-approved runtime with an existing P4 device key and independent, authenticated `read_verified_current_selection()`. It does not start the listener itself.

Exact `POST /p3/selection`:
1. Require `application/json`, one bounded `Content-Length` 1–1024, no Transfer-Encoding, no parameter path.
2. `SignedPlaybackVerifier` checks body exact fields and domain-separated P3 HMAC with paired P4 secret, timestamp and nonce anti-replay.
3. `SignedP3ToOwner` **re-reads current authenticated TV session** and applies P3-TRIGGER owner AUTO + viewer ON + rights checks; old A CLOSE cannot disrupt active B dedup.
4. Only then enqueue existing **private owner V3** event; owner-agent #148 re-checks exact TV+TorrServer file before D1/D2 VI_FAST or LOCAL_EN_DIRECT/LEAN120.
5. 204 empty response on DISPATCH/SKIP; otherwise 403 without exposing why, filename, hash, network address, key or provider output.

No JSON filename is ever accepted; `QueueItem.title` in upstream OMP is for the UI, while owner TorrServer `/torrents get` provides `file_stats[id,path,length]`. The app must be paired to the exact owner PC; P4 AndroidKeyStore pairing alone does not enable P3 sending. P3 has its own OFF-by-default TV toggle in #151.

## Real-world gates not implemented here

This PR **does not** mutate `run_assumed_source_gateway.py` or the installed owner Windows process, and it **does not** automatically enable P3 in the existing P4 server. The existing P4 source gateway is still assumed-source based and lacks a trusted live OMP session reader, a full owner-private TorrServer selected-file connector and V3 activation state. App-only signed event is *origin proof*, not proof that the same file remains playing or that viewers are ON; the trusted callback **cannot be synthesized by trusting event JSON**.

CI is a **loopback localhost** transport test, not a LAN or TV acceptance test. It creates an ephemeral synthetic private certificate, verifies real TLS trust, signed P3 event to temporary private owner inbox, duplicate/tampered refusal, wrong/extra route refusal and unchanged P4 HMAC activation on the SAME server. The test never calls a real provider, TorrServer or Redmi and does not use the user's credentials.

**Before any real owner run**: review gate, exact server/profile mapping, genuine authenticated TV-current-state source, persistent replay/sequence storage across restarts, separate explicit consent for owner Windows listener/config/keys and TV Debug APK. No silent firewall/UPnP/WAN change. Keep Draft/HOLD; no merge until authentic Issue #42 Brain PASS and applicable acceptance.

## Forward path

Build a **disposable** OMP+G1+G2+P4+P3 Debug source with Android Gradle, no installation, then reconcile the real TV status session and owner Windows TorServer read-only resolver. Only after that, owner-supervised on-LAN pairing/POST acceptance, no-provider one-play proof and the separately approved real Gemini/LEAΝ120→P4 no-picker acceptance.
