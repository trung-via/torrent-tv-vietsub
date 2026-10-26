# P0 — Windows TorrServer → Redmi TV: one-pass Human smoke

**Status:** SOURCE_ONLY_DRAFT / WINDOWS_RUN_NOT_REPORTED / REAL_SERVER_UNVERIFIED / REAL_TV_SERVER_E2E_UNVERIFIED.

**Goal:** validate the core path Windows PC running TorrServer → private home LAN → installed Redmi OMP client → lawful video, sound, pause/seek/reopen. This is **independent of G1d UX-01..05** and of G4 unsigned Release binary inspection; do not repeat the five SRT error tests or install a new TV APK.

**Authority:** `docs/PROJECT_CONTRACT.md` C1/C5/C6/C7, ADR-0001, `docs/PRD.md` P0 AC-SERVER/AC-TV and `planning/OMP-EVAL-001-DRAFT.md` Phase C. Human agreed to proceed with one bounded real Windows→TV test on 2026-10-27. This source-only Draft neither implies TorrServer is installed/running nor authorizes unattended TV/Windows changes, CI/AIOS, runner access, installation, firewall/router/service/autostart change, repo merge, or release.

## Source-backed protocol

Pinned OMP `spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` uses `src/api/torrserver.ts` `TorrServerClient.echo()` → **GET `/echo`**, and `list()` → **POST `/torrents`**. We deliberately use **only the read-only `GET /echo`** in the Windows script, and do not list any hashes, update a torrent, stream from PowerShell, or authenticate. TorrServer default HTTP port is **8090**; your setup may use another port/HTTPS. `https://github.com/YouROK/TorrServer` documents the port and `/echo`. TorrServer itself is external to the APK and requires the host PC/NAS to remain on during playback.

**Windows preflight does not prove TV can reach the PC:** the second echo probe hits the PC's LAN address *from the PC*. Only Human observation of OMP on the actual Redmi may establish device connectivity/playback. Using a non-legal torrent or displaying magnet/torrent IDs to collect evidence is out of scope.

## One command, self-detect READY vs BLOCKED

1. On Windows, if TorrServer is already installed, ensure it is started **by your ordinary workflow**; do not let a test script install/start it or open the Windows firewall. If you do not have it, the first probe will report **BLOCKED**, and stop. Do not infer that HTTP probe failure proves TorrServer absent; it may be auth, custom port, TLS, or routing.
2. On Windows, identify the computer's **private LAN IPv4** using its own network settings or `ipconfig`, and keep it private. Use an address in `10.x.x.x`, `172.16–31.x.x`, or `192.168.x.x`. The Redmi and PC should be on the same trusted local network. Do not use 127.0.0.1 on the TV.
3. Review/download the script `poc/server/P0-TorrServer-Windows-Redmi-OnePass.ps1` via GitHub Raw at the pinned source head documented in the Draft PR. Save it in `$env:USERPROFILE\Downloads`. On your **Windows PowerShell 5.1** run the following block *once*:

```powershell
$tsOnePass = "$env:USERPROFILE\Downloads\P0-TorrServer-Windows-Redmi-OnePass.ps1"
if (-not (Test-Path -LiteralPath $tsOnePass -PathType Leaf)) { throw 'STOP: source script missing' }
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $tsOnePass, [ref]$tokens, [ref]$parseErrors
) | Out-Null
if ($parseErrors.Count -gt 0) {
    $parseErrors | Select-Object Message, Extent
    throw 'STOP: local PowerShell parser failed'
}
"P0_TS_PS_PARSE_PASS"
& $tsOnePass -Phase RunOnce
```

4. When prompted for Windows **local loopback** address, press Enter for `http://127.0.0.1:8090`, unless your Windows TorrServer uses a different port or HTTPS (enter that exact loopback base URL). Next, enter the **Windows computer's real private LAN base URL** using the same server port, such as `http://192.168.x.x:8090` (example only). The script rejects WAN, localhost as TV address, URL credentials, query string and arbitrary endpoint paths. It never prints the URL or server body in PASS markers; **PowerShell Read-Host may still echo what you typed**, so do not paste the unredacted transcript.
5. If both `GET /echo` probes return HTTP 200, the script prints:

```text
P0_TS_WINDOWS_LOOPBACK_ECHO_PASS
P0_TS_WINDOWS_LAN_FROM_PC_ECHO_PASS
P0_TS_WINDOWS_PREFLIGHT_PASS_NOT_TV_CONNECTIVITY_PROOF
```

If either fails, it prints `BLOCKED` and stops. **Do not bypass TLS verification, send Basic credentials by plain HTTP, open Windows ports or change routing** just to make this test pass. Diagnose manually in a separate step.

6. Without closing that PowerShell window, use your current Redmi debug OMP app to open its TorrServer/server settings, and manually configure the **LAN URL** entered above. Keep track of any previous server/engine setting so you can restore it if needed. The script **does not** alter Android settings or call ADB. Use only an **already available video you have rights to access** in TorrServer's library; if none is available, type **BLOCKED** at the fixture prompt (do not add/delete torrents or scrape sites as part of this read-only test).
7. The script collects six `PASS` / `FAIL` / `BLOCKED` confirmations **locally, in one run**: OMP TV connects, authorized media available, video and sound playing, D-pad pause/seek, reopen/resume, and manual decision to restore/keep config. If any fails it stops immediately; Human can diagnose a single blocker without a series of chat approvals.

Final completion marker only if all six were manually PASS:

```text
P0_TS_WINDOWS_TORRSERVER_REDMI_HUMAN_E2E_PASS
```

**This is Human-entered TV evidence**, not direct network or ADB instrumentation. Send only the marker lines and an outcome sentence (e.g. server present/blocked and playback yes/no) to the chat; hide LAN IP, server URLs, user/password, media title, magnet, passkey, raw infohash, private Wi-Fi name, and device serial.

## Interpretation

| Result | Meaning / next work |
| --- | --- |
| `P0_TS_WINDOWS_LOOPBACK_ECHO_PASS` | GET /echo responded from local PC. This alone does not establish actual TorrServer binary/version or TV access |
| `P0_TS_WINDOWS_LAN_FROM_PC_ECHO_PASS` | PC can reach its private LAN address. **Not** equivalent to Redmi reaching it |
| `P0_TS_TV_CONNECTION_HUMAN_PASS` | Human reports Redmi OMP loads server library |
| `P0_TS_PLAYBACK_HUMAN_PASS`, `P0_TS_REMOTE_SEEK_HUMAN_PASS`, `P0_TS_REOPEN_HUMAN_PASS` | Human reports essential player control smoke |
| `P0_TS_WINDOWS_TORRSERVER_REDMI_HUMAN_E2E_PASS` | Bounded real Windows→Redmi smoke established for that configuration and legal fixture |
| `BLOCKED` or `FAIL` | Do not claim success or rerun blindly. Record single failing stage and address specific precondition |

**Not covered:** API version, HTTP Range byte compliance, TorrServer authentication/security hardening, real 4K/HDR/other codecs, subtitle transport/import or `.vtt`, embedded track switching, complete G1 acceptance AC-01–06, G2/G3 synchronization, G4 production Release isolation, source-search adapters and long-duration LAN stability. These remain separate gates after the core playback path is proven.

**Source-only PR effects:** two additive files under `poc/server/`; **zero** workflow/CI edits, no app code change, no server/TV operation. Main and existing Draft PRs remain unchanged.
