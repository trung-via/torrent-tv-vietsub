# Exact Owner-session P3 / P2 / P4 live activation

Scope: Draft PR #162. This is source/owner handoff, NOT a report that private
P4 LAN or visible no-picker subtitles have already passed on Redmi.

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

## Private, exact-media opt-in

The owner must create an ACL-protected p3-p4-policy.json under the EXISTING
%LOCALAPPDATA%\TorrentTVVietsub\OwnerBridge directory. The file must use
schema TTV-P3-P4-OWNER-POLICY-V1 and contain exactly:

- enabled: boolean (true only on explicit owner opt-in)
- profile_id: existing preconfigured TorrServer owner-local profile identifier
- torrserver_port: existing local read-only TorrServer high port
- private_media_root: absolute path for the owner's approved complete files
- media: up to 32 owner-approved exact entries, each with torrent_hash,
  file_index, torrserver_path, video_path, rights_approved boolean

Example values below are SYNTHETIC and must never be taken as real permissions:
profile_id=test-owner-profile, torrserver_port=8090, torrent_hash=40 'a'
characters, file_index=2, torrserver_path=Authorized/Synthetic.Film.2017.mkv,
video_path=an owner-local absolute private path to that exact synthetic file.

An approved entry is NOT a blanket right or proof of a Vietnamese track.
Before positive rights, the real owner local TorrServer GET metadata must
match the exact torrent/profile/file index and path and the local completed
video size; the file must be inside the pinned root, no symlink or path
traversal. Missing file, mismatch, stale TV state or absent approval is HOLD.
VI state is assessed by real ffprobe on that exact local video, plus local
Vietnamese sidecars. Missing ffprobe, unlabelled/ambiguous tracks or streaming
without a local completed file gives UNKNOWN/HOLD, not fabricated ABSENT.
Owner-side inventory is NOT independent proof of every subtitle track shown
by the TV, which remains a real-device acceptance check.

## Deployment and consumer gate

1. On the logged-in Windows owner account only, the existing trusted
   install-owner-session-bridge.ps1 can copy the updated D2/P2 Python source
   and launcher into the owner-private app. Source updates in GitHub do NOT
   magically replace the previously installed copy or change its task.
   If old Owner Agent is running, user-side transition is needed; do not kill
   it from the NETWORK_SERVICE runner.
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

Status boundaries until observed: SOURCE_IMPLEMENTED, CI_ONLY for policy and
launcher tests, LIVE_OWNER_NOT_DEPLOYED, REAL_PAIR_LAN_NOT_RUN,
P4_REDMi_NO_PICKER_NOT_RUN, MERGE_HOLD under Issue #42.
