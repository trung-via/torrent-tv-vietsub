# P4 owner-local PC HTTPS onboarding (Draft PR #118)

**Scope:** one *manual*, foreground, synthetic-only Windows PC gateway for a trusted home LAN. The installed Redmi P4 Debug APK comes from Draft PR #120. This page does not prove a live TV handshake or subtitle render and does not request any real film, private API credentials or cloud translation.

## Current proof vs pending

- Source and Windows CI/Android builds have passed in the separate PRs. Owner Debug APK installation on Redmi was verified in Actions run `43273786878` by `adb install -r` and post-install SHA256.
- Gateway `run_assumed_source_gateway.py` supports HTTPS with a matching private key/certificate, per-device 32-byte key, exact `media.<64hex>` source identity, signed activation/read and mock 120→240 cumulative SRT.
- **Not yet demonstrated:** Windows private IP-SAN certificate/owner pairing provisioned, a PC listener accessible by Redmi, a live authenticated activation from the native player, or 120→240/cue131 visibly rendered.

## One owner laptop setup (not CI)

Use the **Windows PC private IPv4 address**, not the Redmi TV's address. It must be assigned to this PC. Keep all values and files off public GitHub and ChatGPT logs.

In a local checkout of Draft PR #118, Windows PowerShell (interactive owner session):

```powershell
# Inspect the local PC NIC privately to choose its current IPv4
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object AddressState -EQ 'Preferred' |
  Select-Object InterfaceAlias, IPAddress

# Replace with the PC LAN IPv4, NEVER the TV IP; example is a placeholder
$pcPrivateIp = '<PC_PRIVATE_IPV4>'
& .\poc\p2-aisub\prepare_p4_owner_pc.ps1 -BindIPv4 $pcPrivateIp -Port 19009
```

Prerequisites: Windows PowerShell 5.1+, OpenSSL in PATH or a standard local Git installation, one preferred private IPv4 on the selected network interface, and permission to write the current user's `LOCALAPPDATA`.

The preparation script:

- **Rejects GitHub CI**, non-RFC1918 addresses, addresses not assigned to the PC, and pre-existing pairing directories (no silent key rotation).
- Creates an owner-only ACL directory at `%LOCALAPPDATA%\TorrentTVVietsub\P4`.
- Generates a 30-day self-signed TLS leaf cert with **exact IP Address SAN**, a private key, a fresh 32-byte random device key, and the PC pin SHA256.
- Keeps `pc-cert.pem`, `pc-key.pem`, `pairing-key.hex`, `pairing-token.txt` and `gateway-bind.txt` private. Do **not** paste any token or key into GitHub/ChatGPT.
- Does **not** open a port, start a service, change Windows Firewall, install an APK or call Gemini.

**Do not use this self-signed developer cert as an Internet-facing public service.** After the 30-day certificate expires, explicit revocation/re-pairing is required.

## Run synthetic-only HTTPS without entering a film identity

**Debug acceptance only:** the TV's existing **Bật Vietsub AI** action sends
its opaque `media.<64hex>` identity in an HMAC-authenticated HTTPS activation
request. The trusted owner PC checks the pinned pairing secret first, then
binds the **first authenticated film** to synthetic SRT cues 1–240. This
acceptance fixture does **not** claim to find matching real subtitles, and
refuses activation for any second film. Real subtitle/API operation still
requires a matching authorized SRT/VTT and exact media/source identity.

The owner explicitly starts this temporary home-LAN listener in the local
PowerShell session, from an up-to-date checkout of Draft PR #118:

```powershell
# No media key, token, TV confirmation or extra pairing input required.
# No API call, firewall service or public WAN listener is started.
& .\poc\p2-aisub\start_p4_mock_gateway_owner.ps1
```

While that foreground command is running, play an authorized test item in OMP
VLC and select **Bật Vietsub AI**. This is per-film subtitle opt-in, *not*
a pairing request. Expect the PC to publish mock versions 120 and then 240.
At normal playback timestamps near cue 131 (4m22s) check Vietnamese synthetic
caption only after the TV actually ingests it; do not claim an E2E PASS from
PC publishing alone. Use Ctrl+C to close the listener.

The script reads the local, ACL-protected materials and launches the P2 CLI using `--start-lan --mock-revisions` with **no `--source` and no `--execute-api`**. It does not invoke TorrServer, Gemini, a background scheduled task or a Windows service. It does not open/configure Windows Firewall; if inbound traffic is blocked, **stop and request a specific owner firewall decision**, never disable TLS checks or open WAN.

For this ONE-laptop setup, there is **no D-pad pairing dialog, token typing or confirmation**. The owner-local gateway launcher silently calls `auto_pair_owner_redmi_adb.ps1` once, which stages the existing private token via the authenticated owner ADB connection into the Debug app. The next native PlayerActivity load imports it into AndroidKeyStore and deletes the plaintext staging file. The Windows owner-local staging receipt prevents repeated ADB transfers on later launches.

The app connects to the saved laptop's pinned HTTPS identity; it must **not** accept an arbitrary LAN responder just because only one laptop is expected. New TV installation requires the updated P4 Debug APK; an older installed build still has the manual dialog. If ADB is unavailable on first enrollment, stop safely rather than falling back to unauthenticated network pairing.

The **Bật Vietsub AI** action is about explicit consent to process subtitles for the currently playing film, not a pairing confirmation. No per-film token entry is required.

## Actual proof required before P4 HTTPS E2E PASS

Record separately, with no private identifiers in public artifacts: successful HTTPS activation and authenticated GET; pinned certificate and exact IP SAN; synthetic cumulative SRT 120 then 240 including cue 131 on Redmi; same-item VLC/G2 refresh with first-frame ACK; OFF/OTHER refusal; film switch and network failure rollback. Test only licensed/authorized fixtures. The gateway may be stopped with Ctrl+C; afterward no service remains listening.

**No real Gemini API call, release build, auto-merge, firewall adjustment, raw TorrServer/MCP or WAN exposure is included in this step.**
