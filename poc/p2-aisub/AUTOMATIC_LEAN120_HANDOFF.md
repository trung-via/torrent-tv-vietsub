# Automatic EN SRT/VTT to LEAN120 Gemini to private VI subtitles to P4

Status: Draft PR #118 candidate implementation, NOT merged main and NOT a live
Gemini API / real translated-film Redmi acceptance.

## Operation (one trusted Windows laptop)

1. An owner-authorized source/discovery workflow places a checked and exact
   media-to-English-file entry in an owner-private source manifest. Upstream D1,
   D2 and D3 are responsible for source/release matching. No match is inferred
   from a filename, subtitle wording, a torrent or arbitrary network input.
2. OMP plays that exact media. Human selects "Bật Vietsub AI" on the Debug TV.
   The TV sends its opaque media key through the existing pinned-HTTPS/HMAC
   activation. Only after HMAC verification does the owner PC resolve a
   matching local source file. Wrong media or unmatched source is refused.
3. The new AutomaticLean120Worker uses the existing P2 Gemini REST adapter,
   progressing automatically by at most 120 target cues and 6500 target
   characters per window, with +/-4 read-only context and fixed glossary.
   Exact ID/order/cue timestamps and UTF-8 are validated for every revision.
   Human does NOT step through windows or manually select the TV SRT.
4. Each complete window is stored atomically in a PRIVATE owner directory
   before its cumulative revision is published to existing P4 Signed Feed.
   The last revision also becomes vi-final.srt (or vi-final.vtt).
5. On reactivation, completed checkpoints replay to the newly paired TV
   session with NO duplicate Gemini requests for cached windows. If a batch's
   provider result is uncertain, the worker leaves an .inflight marker and
   STOPS pending explicit local reconciliation; it must never blindly re-bill.

The existing P4 sender/receiver and OpenSubtitles branch remain unchanged.
This is NOT a second TV receiver, a duplicate translator, an Android install,
an automatic Windows service, or a cloud job on GitHub.

## Private verified English handoff

The trusted producer writes only to the owner's private profile:

    %LOCALAPPDATA%\TorrentTVVietsub\P2\verified-en-manifest.json

JSON example with INVALID placeholders to replace privately:

    {
      "schema": "TTV-P2-OWNER-MATCHED-EN-V1",
      "sources": [
        {
          "media_key": "media.<64-lowercase-hex-digits>",
          "format": "srt",
          "source_path": "<ABSOLUTE_LOCAL_OWNER_PATH>.srt",
          "source_sha256": "<64-lowercase-hex-digest>",
          "owner_confirmed_match": true
        }
      ]
    }

Exact owner-confirmed match, SHA256, local absolute path, SRT/VTT format and
strict sequence/timestamp validation are mandatory. At most 32 entries.
The owner-confirmed flag is a claim from a trusted source workflow, NOT
proof that OpenSubtitles live discovery or release matching has been accepted.
D3 must build this trusted manifest from D1/D2/D2.5; that integration is NOT
yet implemented. It must NOT forge a match or automatically upload random
subtitles to Gemini.

## Configurable model example for the specifically authorized Thor pilot

The PRIVATE model profile can be written to:

    %LOCALAPPDATA%\TorrentTVVietsub\P2\translator-profile.json

Example JSON:

    {"provider":"gemini","model":"gemini-4-hydrogen","thinking_level":"high"}

The Human-confirmed default API profile is now **Gemini 4 Hydrogen /
thinking HIGH**, and `translator_profile.json` in the active P2 branches
contains this model ID. An optional private owner profile may override it.
Adapter support for an ID does NOT prove that the owner-held Gemini API key
can call it; live provider authorization, quota/cost, actual endpoint access
and translation quality are separate acceptance gates. No automatic fallback
to the previous Gemini Flash model is authorized.

## Explicit foreground start on the Windows owner laptop

Prerequisite: owner-local source manifest and profile, current GEMINI_API_KEY
in the owner's process environment, and existing private P4 TLS pairing.
Start from the checked-out Draft PR #118 branch, with explicit consent to
send the pre-approved English dialogue to the Gemini API:

    & .\poc\p2-aisub\start_p4_auto_lean120_owner.ps1 -AuthorizeCloudTranslation

The script refuses to run on GitHub Actions, refuses missing key/profile/
source/owner pairing, checks that the chosen RFC1918 IP belongs to the PC and
never changes Windows Firewall, router, APK, ADB pairing or TorrServer.
The script is foreground-only and can be stopped with Ctrl+C. Do not
publish private values in chat logs, issues or this PUBLIC GitHub repo.

When the trusted TV activates a specific media already in the manifest,
the LEAN120 worker automatically performs every batch and P4 receives each
validated cumulative revision. No per-batch manual script required.

Private outputs reside in:

    %LOCALAPPDATA%\TorrentTVVietsub\P2\auto-lean120-state\
        <opaque-job-digest>\batch-0001.json
        <opaque-job-digest>\batch-0002.json
        <opaque-job-digest>\vi-final.srt

Output may include copyrighted dialogue. Treat the owner-only state folder,
manifest and original file as private. The API key is never written to the
checkpoint and is never committed to the public repository.

## Remaining limits / acceptance

- Real Gemini calls, billing, actual model availability and quality: NOT RUN.
- Real English media/release verification from OpenSubtitles D3: NOT RUN.
- Actual VI film text received over P4 on Redmi: NOT RUN.
- TV automatic session fanout while a duplicate activation is already
  translating: NOT IMPLEMENTED; an exclusive per-job lock refuses duplicate
  paid requests, avoiding quota reuse and wrong-feed claims.
- Unknown provider effect: STOP with .inflight, not an automatic retry.
- Restarting the gateway alone does not prove automatic TV reconnection.
- Previous synthetic P4 Human PASS still stands; it is not proof for this
  new real-Gemini path.
- CI uses fake Gemini responses and synthetic subtitle text only.
