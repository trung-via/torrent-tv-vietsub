# P4 — TLS-only PC/TV LAN acceptance (Draft)

**Status:** Source candidate in stacked PR #120; PC counterpart in Draft PR #118.
This is not proof of a real LAN exchange, an installed TV APK, a Gemini request
or production release.

## User experience / boundaries

1. The single authorized PC maintains a **unique device-level 32-byte random pairing key**,
   and a TLS certificate/private key pair outside the public repository. The
   certificate contains a **subjectAltName of type IP Address**, matching the
   exact RFC1918 IPv4 PC address. Neither secrets nor subtitle source bytes
   are stored in GitHub Actions, issue comments, screenshots or public artifacts.
2. Explicit owner-only PC command for the P2 gateway supplies
   `--start-lan --bind <PRIVATE_IP> --port <PORT> --tls-cert <LOCAL_CERT_PEM>
   --tls-key <LOCAL_PRIVATE_KEY_PEM>`. Missing/invalid cert or key fails
   **before** a listener is opened. `--mock-revisions` emits synthetic
   120→240 SRT only; it cannot be combined with `--source` or
   `--execute-api`. Actual API calls are a separate private gate.
3. The PC prints `P4_TLS_CERT_SHA256=<64 lowercase hex>`, the SHA-256 of the
   PEM leaf certificate's DER. Verify this fingerprint through a trusted
   local/out-of-band channel; this text is public, but the 32-byte device
   key is secret. No automatic network transfer of the master key.
4. **ONE OWNER LAPTOP DEBUG-ONLY:** the already authorized Windows PC
   stages its existing owner-private pairing token over authenticated ADB
   stdin, using Android `run-as` only for the Debug app. OMP consumes
   `files/p4-owner-bootstrap-v1.txt` on native player entry, imports the
   unique PC IP:port, HMAC key and SHA256 certificate pin into AndroidKeyStore
   AES-GCM and deletes the temporary plaintext input. No D-pad token input,
   confirmation dialogs, discovery broadcast or trust-on-first-use network
   handshake. A different laptop is never silently accepted; an existing
   pinned pairing is not overwritten. This is **owner-PC auto-recognition**,
   not general-purpose insecure discovery of any LAN host. An expired/change
   of certificate requires a controlled re-provision, not TLS bypass.
   `Hủy ghép đôi PC Vietsub AI` remains a deliberate revoke action.
   Legacy HTTP credentials are not reused.
5. **Bật Vietsub AI** for the current film creates signed paired activation
   over **HTTPS**, then pulls signed revisions over **HTTPS** only. The Android
   TLS client requires an exact RFC1918 IPv4 host, TLS 1.2, nonexpired leaf
   cert, **SHA-256 pin match** and an exact IP Address SAN. It does not install
   a trust-all certificate manager or override the default hostname verifier.
   The existing HMAC, signed revision, exact film/source/nonce, OFF/OTHER,
   first-frame ACK, last-good G1/G2 rollback, and replay cursor remain intact.

## Threat / negative-test checklist

- HTTP endpoint, invalid or missing pin, wrong IP SAN, changed cert, expired
  cert, TLS version below 1.2 -> **fail closed**, never fall back to HTTP.
- Activation request with another media key, old nonce or wrong HMAC -> reject.
- Revision GET without authorization, repeated nonce, wrong session/source,
  altered payload or old revision -> reject without changing the G1 registry.
- Film change, pause, seek, explicit OFF/OTHER, process restart and network
  drop -> no unauthorized subtitle selection or stale "applied" cursor.
- Confirm TLS is used for BOTH activation and subtitle GET, not only one leg.
- A real PC service / firewall / subnet change needs explicit owner authority.
  CI must not open LAN listeners, publish files or install APKs.

## Build / device evidence gates

- **P2 offline unit CI:** source/mock and TLS preflight only; no real PC LAN.
- **P4 hosted Python / Kotlin:** exact source guards, overlay and HMAC.
- **P4 dedicated Windows Android:** OMP + G1 + G2 + P4 on a disposable pinned
  checkout, `assembleDebug testDebugUnitTest`, record APK SHA256; no install.
- **PC/TV test (separate authorization):** trusted local cert and pairing;
  synthetic authorized media and mock SRT 120→240, cue 131 visibly on Redmi
  with no document picker, OFF/OTHER, rollback on fault. Verify real HTTPS
  handshake and no plaintext transfer using permitted network observations.
- **G4 release:** independent signed artifact, licensing, rollback and approval.

The PC HTTPS listener does not control TorrServer or expose its admin/MCP.
Never expose this P4 gateway on WAN, change Firewall or disable platform TLS
checks as a workaround. A public repo is not a place for PC private keys.
