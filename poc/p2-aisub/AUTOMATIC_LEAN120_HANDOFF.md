# Automatic EN SRT/VTT to LEAN120 Antigravity to private VI subtitles to P4

> Historical Draft #118 architecture note. For current source and executable
> commands, follow [Antigravity Owner Guide](ANTIGRAVITY-OWNER-CURRENT.md)
> and Draft #173; the old Gemini Developer API route is retired.

Status: Draft PR #118 candidate implementation, NOT merged main and NOT a live
Antigravity CLI / real translated-film Redmi acceptance.

## Operation (one trusted Windows laptop)

1. An owner-authorized source/discovery workflow places a checked and exact
   media-to-English-file entry in an owner-private source manifest. Upstream D1,
   D2 and D3 are responsible for source/release matching. No match is inferred
   from a filename, subtitle wording, a torrent or arbitrary network input.
2. OMP plays that exact media. Human selects "Bật Vietsub AI" on the Debug TV.
   The TV sends its opaque media key through the existing pinned-HTTPS/HMAC
   activation. Only after HMAC verification does the owner PC resolve a
   matching local source file. Wrong media or unmatched source is refused.
3. The AutomaticLean120Worker uses the current P2 Antigravity CLI gateway,
   progressing automatically by at most 120 target cues and 6500 target
   characters per window, with +/-4 read-only context and fixed glossary.
   Exact ID/order/cue timestamps and UTF-8 are validated for every revision.
   Human does NOT step through windows or manually select the TV SRT.
4. Each complete window is stored atomically in a PRIVATE owner directory
   before its cumulative revision is published to existing P4 Signed Feed.
   The last revision also becomes vi-final.srt (or vi-final.vtt).
5. On reactivation, completed checkpoints replay to the newly paired TV
   session with NO duplicate Antigravity requests for cached windows. If a batch's
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
subtitles to an unapproved provider.

## Current owner-local model profile

The PRIVATE model profile can be written to:

    %LOCALAPPDATA%\TorrentTVVietsub\P2\translator-profile.json

Example JSON:

    {"provider":"antigravity","model":"gemini-4-hydrogen-high","thinking_level":"high"}

The source default is **Antigravity CLI, Gemini 4 Hydrogen High alias**.
The `thinking_level` must match the model alias suffix, preventing a silently
ignored configuration. CLI support for the alias and real Windows availability
remain unverified; the source does not invent undocumented reasoning flags.
An optional private owner profile may override this only with a coherent
model alias and level. There is no automatic provider/model fallback.

## Explicit foreground start on the Windows owner laptop

Prerequisite: owner-local source manifest and profile, signed-in Antigravity
CLI in the *interactive* Windows owner account, and private P4 TLS pairing.
Review the currently installed CLI syntax first. The old Draft #118 command
below is historical and **must not be used** for the current provider:

    & .\poc\p2-aisub\start_p4_auto_lean120_owner.ps1 -AuthorizeCloudTranslation

Use the exact current flags in the [owner guide](ANTIGRAVITY-OWNER-CURRENT.md)
for dry-run and explicitly authorized cloud upload. No GitHub Actions or
service-account session may be treated as the owner CLI identity. No step
here authorizes changes to Windows Firewall, router, APK, ADB or TorrServer.

When the trusted TV activates a specific media already in the manifest,
the LEAN120 worker automatically performs every batch and P4 receives each
validated cumulative revision. No per-batch manual script required.

Private outputs reside in:

    %LOCALAPPDATA%\TorrentTVVietsub\P2\auto-lean120-state\
        <opaque-job-digest>\batch-0001.json
        <opaque-job-digest>\batch-0002.json
        <opaque-job-digest>\vi-final.srt

Output may include copyrighted dialogue. Treat the owner-only state folder,
manifest and original file as private. No private credential or dialogue may
be committed to the public repository.

## Remaining limits / acceptance

- Real Antigravity calls, quota, actual model availability and quality: NOT RUN.
- Real English media/release verification from OpenSubtitles D3: NOT RUN.
- Actual VI film text received over P4 on Redmi: NOT RUN.
- TV automatic session fanout while a duplicate activation is already
  translating: NOT IMPLEMENTED; an exclusive per-job lock refuses duplicate
  paid requests, avoiding quota reuse and wrong-feed claims.
- Unknown provider effect: STOP with .inflight, not an automatic retry.
- Restarting the gateway alone does not prove automatic TV reconnection.
- Previous synthetic P4 Human PASS still stands; it is not proof for this
  new real-Antigravity path.
- Offline tests use fake CLI responses and synthetic subtitle text only.
