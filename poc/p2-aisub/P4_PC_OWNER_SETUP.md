# P4 owner-local PC HTTPS onboarding (Draft PR #118)

**Scope:** one *manual*, foreground, synthetic-only Windows PC gateway for a trusted home LAN. The installed Redmi P4 Debug APK comes from Draft PR #120. This page does not prove a live TV handshake or subtitle render and does not request any real film, private API credentials or cloud translation.

## Current proof vs pending

- Source and Windows CI/Android builds have passed in the separate PRs. Owner Debug APK installation on Redmi was verified in Actions run `43273786878` by `adb install -r` and post-install SHA256.
- Gateway `run_assumed_source_gateway.py` supports HTTPS with a matching private key/certificate, per-device 32-byte key, exact `media.<64hex>` source identity, signed activation/read and mock 120→240 cumulative SRT.
- **Not yet demonstrated:** Windows private IP-SAN certificate/owner pairing provisioned, a PC listener accessible by Redmi, the native player submitting the matching media key, or 120→240/cue131 visibly rendered.

## Owner-only PC preparation (not CI)

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

## Start synthetic-only HTTPS after choosing the exact media identity

The gateway uses the **exact OMP active `media.<64hex>` key**. The current prototype does not expose a trusted, automated media-key export to PC. Obtaining/validating that key through the local TV UI or a bounded private handoff is a separate acceptance blocker. Do not substitute a hardcoded demo key to claim real TV delivery.

After that key is established *privately* and the owner chooses to run a temporary PC LAN listener:

```powershell
# Run only from the owner PC, not from GitHub CI; foreground until Ctrl+C
$activeMediaKey = '<EXACT_CURRENT_OMP_MEDIA_KEY>'
& .\poc\p2-aisub\start_p4_mock_gateway_owner.ps1 -MediaKey $activeMediaKey
```

The script reads the local, ACL-protected materials and launches the P2 CLI using `--start-lan --mock-revisions` with **no `--source` and no `--execute-api`**. It does not invoke TorrServer, Gemini, a background scheduled task or a Windows service. It does not open/configure Windows Firewall; if inbound traffic is blocked, **stop and request a specific owner firewall decision**, never disable TLS checks or open WAN.

On Redmi, open OMP native D-pad **Ghép đôi PC Vietsub AI**, and enter the contents of the **local private** `pairing-token.txt` as a single value. The TV stores the key and certificate pin in AndroidKeyStore-sealed app-private data. Then, on a permitted synthetic test film with matching media identity, use **Bật Vietsub AI**. If the source mapping fails, it must show a controlled failure, not generate or invent a replacement film subtitle.

## Actual proof required before P4 HTTPS E2E PASS

Record separately, with no private identifiers in public artifacts: successful HTTPS activation and authenticated GET; pinned certificate and exact IP SAN; synthetic cumulative SRT 120 then 240 including cue 131 on Redmi; same-item VLC/G2 refresh with first-frame ACK; OFF/OTHER refusal; film switch and network failure rollback. Test only licensed/authorized fixtures. The gateway may be stopped with Ctrl+C; afterward no service remains listening.

**No real Gemini API call, release build, auto-merge, firewall adjustment, raw TorrServer/MCP or WAN exposure is included in this step.**
