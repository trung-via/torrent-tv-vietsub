# Exact Owner-session P3 / P2 / P4 live activation

Scope: Draft PR #162, updated for Human-approved R0 personal/FLAT decision
[#170](https://github.com/trung-via/torrent-tv-vietsub/issues/170).
This is source/owner handoff, NOT a report that private P4 LAN or visible
no-picker subtitles have already passed on Redmi.

## Reuses the installed architecture, not a second worker

The existing logged-in owner's TorrentTV-Vietsub-OwnerAgent scheduled task
calls start-owner-session-agent.ps1. If the private OwnerBridge directory has
no p3-p4-policy.json, the launcher preserves the old behavior. If a policy
is present, it invokes owner_p3_p4_entrypoint.py --start-lan, which reuses
the same V3 event loop, existing D1/D2 VI-first lookup, existing Gemini
4 Hydrogen High LEAN120 worker, and signed P4 feed. Invalid policy is HOLD,
never fallback to permissive mode. Opening a movie does NOT itself authorize
API work; the signed per-film viewer REQUESTED state and tap are required.

The one previously paired P4 identity comes from the logged-in owner's
%LOCALAPPDATA%\TorrentTVVietsub\P4. The 32-byte key, IP:port, IP-SAN
cert/key and original TV bootstrap receipt are mandatory. Existing private
cert/key bytes are staged inside protected OwnerBridge/p4-identity without
rotating the certificate pinned by the TV. Missing/stale pairing or Session 0
must HOLD. No GitHub runner may read that directory or impersonate the owner.

## Private one-tap personal mode and legacy per-film pinning

The owner must create an ACL-protected p3-p4-policy.json under the EXISTING
%LOCALAPPDATA%\TorrentTVVietsub\OwnerBridge directory. The file must use
schema TTV-P3-P4-OWNER-POLICY-V1 and contain exactly:

- enabled: boolean (true only on explicit owner opt-in)
- profile_id: existing preconfigured TorrServer owner-local profile identifier
- torrserver_port: existing local read-only TorrServer high port
- private_media_root: an absolute owner-private directory for local files or stream-only state
- media: `[]` selects the approved personal single-owner one-tap mode. An optional nonempty list retains up to 32 **legacy exact pins** with torrent_hash, file_index, torrserver_path, video_path, rights_approved. Legacy stream-only pins additionally require stream_only=true and video_path=null.

In personal mode, the logged-in owner opts in once with `enabled=true` and
`media=[]`; **no film needs advance enrollment**. The viewer's explicit
per-film **Bật Vietsub AI** action still must arrive through the existing
paired, signed, fresh TV session. The owner verifies matching selected
hash/index from its configured localhost `POST /torrents` response, validates
the selected video path and nonzero length, and checks embedded VI tracks via
the same localhost `/ffp` reader. `UNKNOWN` keeps the request waiting; VI
`PRESENT` reuses it. Nothing is inferred from TV-provided titles, and no
artificial local video/EN sidecar is created. The owner remains responsible
for using media and subtitle sources they may lawfully access.

Example values below are SYNTHETIC and must never be taken as real permissions:
profile_id=test-owner-profile, torrserver_port=8090, torrent_hash=40 'a'
characters, file_index=2, torrserver_path=Authorized/Synthetic.Film.2017.mkv,
video_path=an owner-local absolute private path to that exact synthetic file.

An approved legacy entry is NOT a blanket right or proof of a Vietnamese track.
Both modes require current paired signed TV identity, explicit per-film user
request and an exact owner-configured localhost TorrServer POST /torrents
selected file. Personal mode uses owner-wide opt-in plus the current explicit
viewer choice; legacy pinned mode requires independent per-film approval.
A locally complete pinned file is additionally
pinned to the owner-private media root and matched by file size, with local
ffprobe and VI-sidecar inspection.

For stream-only, no fake video path is created. Reuse the upstream OMP
TorrServerClient.probe() endpoint GET /ffp/<hash>/<index> constructed solely
from the owner-pinned localhost port and independently checked selected hash/
file index. Strict 3-second and 64-KiB bounds, no redirect/proxy/TV-supplied
URL, no stream URL, no cloud request. The TorrServer ffprobe may internally
request torrent data to inspect tracks, so it is invoked only after matching
personal owner opt-in or legacy exact pin. No video data is copied by this application.

A response must contain an actual video stream and a bounded list of clearly
identified subtitle languages. Vietnamese embedded stream -> PRESENT;
known non-VI embedded languages or no embedded subtitles -> ABSENT for this
EMBEDDED inventory only. Unknown/und language, empty/invalid ffprobe JSON,
missing video, inaccessible endpoint (including auth), timeout, or stale
TorrServer identity -> UNKNOWN/HOLD. This does NOT independently certify
the absence of an external Vietnamese subtitle track selected on the TV;
native OMP track inventory remains a required real-device acceptance gate.

For a verified personal or legacy stream-only source, V3 passes local_source=None to the
EXISTING VI_FAST OpenSubtitles D1/D2 route, then any EN source uses the
EXISTING P2 Gemini 4 Hydrogen High LEAN120 adapter and the EXISTING
authenticated P4 receiver. Neither a second translator nor a second
subtitle picker/receiver is added.

Synthetic stream-only policy values (NOT real permissions):
video_path=null, stream_only=true, torrent_hash=40 'a' characters,
file_index=2, torrserver_path=Synthetic/Synthetic.Authorized.2017.mkv,
rights_approved=true. Keep all real hashes, private directories, keys, IPs
and subtitles outside this PUBLIC GitHub repository.

## Deployment and consumer gate

1. For an Owner already running R0, use the new read-only-by-default
   `hostops/setup/owner-r0-personal-policy-offline-upgrade.ps1` after obtaining
   the reviewed source. Its inspection verifies the existing owner task and
   exact policy module. The owner must then explicitly disable and stop the
   task, verify no Python Owner worker or pending/inflight job, and run the
   script with `-ApplyOffline`. It preserves a private backup and replaces
   **only** the original policy module; it never restarts the task. If the
   installed module differs from the pinned baseline, it HOLDS. Source
   updates in GitHub do NOT update the running Python process. Do not use
   the broad legacy installer to apply this single-module R0 upgrade.
   After install, the logged-in owner may re-enable/start the same task and
   separately verify a new PID, heartbeat and fresh on-TV selection receipt.
2. Use the existing P4 pairing: never regenerate a leaf cert or key silently,
   reset TV app data, or open Firewall/WAN. Do not trigger paid API work until
   a verified signed per-film event and existing source rights are present.
3. Observe an authorized sample film on the exact OMP Debug APK: TV REQUESTED
   event -> owner exact metadata -> source VI or completed EN-to-VI -> P4
   signed activation/read -> displayed Vietnamese cue in native VLC without
   picker. Verify OFF/OTHER, seek, audio preservation, A-to-B-to-A.
4. Current ready registry publishes a single final completed VI revision;
   true progressive 120-to-240 delivery and visible cue 131 remain a separate
   product/acceptance gate and must NOT be declared passed from this setup.

Status boundaries for this new R0 policy change until observed:
SOURCE_IMPLEMENTED, CI_ONLY for policy and launcher tests,
LIVE_OWNER_POLICY_NOT_DEPLOYED, REAL_PAIR_LAN_NOT_RUN,
P4_REDMi_NO_PICKER_NOT_RUN, MERGE_HOLD under Issue #42.
