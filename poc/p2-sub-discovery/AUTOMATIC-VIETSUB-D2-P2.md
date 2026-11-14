# Torrent TV automatic D2 → P2 handoff (no per-film Human steps)

Owner decision, 2026-11-14: **after a confidently selected subtitle is
downloaded and cached, automatically start the existing Gemini 4 Hydrogen /
HIGH LEAN120 translation**. Do NOT ask for `DOWNLOAD ONE`, do NOT run a
separate cache-verification PowerShell command, and do NOT ask Human to run
the model CLI for each film. Keep internal checks; they are not user tasks.

## Minimal runtime pipeline

```text
Trusted selected-media event (TorrServer filename from current media)
    |
    v
AutomaticVietsubFlow.selected_media(name)
    |
    +--> VI_FAST metadata / confident VI -> one download -> private VI cache
    |                                                 (no Gemini)
    |
    +--> confident EN -> one download -> private EN cache
                                        |
                               immediate in-process callback
                                        |
                           after_en_cached(asset,path)
                                        |
                        existing P2 cached_en_direct_handoff
                                        |
                  existing Gemini 4 Hydrogen High LEAN120 worker
                                        |
                   private checkpoint / final Vietnamese SRT
                                        |
                    D3/P4 media binding & TV delivery (separate)
```

The automated path does **not** call the old owner trial CLI with prompts.
It also does not add a second translator, duplicate search, model runner,
queue/bus, SRT copy, extra checksum command, D3 manifest or TV action in
the translation path. The existing D2/SRT/worker validators still run
inside the process and stop quietly on wrong-source/uncertain outcomes.

## Integration API (called by the local owner process)

```python
# Once when the owner's authenticated local app process starts:
flow = build_owner_auto_flow(
    enabled=owner_local_auto_vietsub_preference,
    cache_root=owner_private_en_cache,
    state_root=owner_private_p2_checkpoints,
)

# ONE callback from the trusted active media source, for every new film:
result = flow.selected_media(selected_video_filename)

# If an already-running D2 path has just cached a selected English asset,
# it can hand over directly WITHOUT searching/downloading again:
flow.after_en_cached(english_asset, private_cached_path)
```

One-time process initialization requires access to the owner-provisioned
`OPENSUBTITLES_API_KEY` and `GEMINI_API_KEY` through the owner process
environment/secure credential provider. **Never** put keys in PUBLIC GitHub
workflows, issue comments, tests or user-visible command output. The app
reads its local stored auto-Vietsub preference *once*, and the owner gives
the upload authorization as an app-level setting rather than repeating it
for each movie. A no-subtitle GET checks Hydrogen availability once at
startup, not between download and translation. If the configured Gemini
Developer API does not offer the selected Hydrogen model, the process
fails closed: no source upload, no Flash fallback.

The factory guards against running live provider calls on GitHub CI.
Windows/GitHub self-hosted runner *service accounts* must not be assumed
to have access to the same DPAPI credentials or subtitle cache as the
owner's interactive Windows user.

## Private idempotency / failure recovery

After SRT validation and cache write, a minimal **private** per-video
`.auto-source-<digest>.json` receipt stores only language, private cache
basename, SHA-256 and count. On repeated media events or process restart,
the owner process verifies cached bytes automatically and resumes the
existing LEAN120 checkpoints; zero repeat provider GET, POST or model
requests for already completed windows. If provider POST is uncertain,
the existing one-attempt marker blocks a second paid POST. If Gemini
result is uncertain, its existing `.inflight` checkpoint blocks a blind
retry. No Human needs to approve or recheck successful batches.

Unknown/ambiguous release or SDH-only source goes to a non-interactive
`REVIEW_REQUIRED` outcome. Correct title/year/source/group/resolution/
codec and timed SRT/SHA/sequence are internal safety conditions, not
extra interactive steps. A local-only synthetic media namespace never
proves real TV/movie sync.

## What has / has not been installed

- **Implemented in Draft PR #140:** pure owner-local D2/P2 callback and
  persistent cache reuse, one-time preconfigured runtime builder.
- **Tested:** fake provider / fake Gemini; real unchanged LEAN120 worker,
  automatic 120+5 windows, no keyboard prompts, VI shortcut, title/group
  mismatch fail closed, repeat events and process restart with 0 duplicate
  provider/model calls. Exact CI run/HEAD in PR #140.
- **Not yet deployed on Windows / real OMP:** there is no authenticated
  selected-media event wired to this new factory in the deployed owner
  process. Installing one-time credential provisioning / OMP event binding
  needs actual owner-Windows account access and runner identity proof. The
  GitHub connector alone cannot install or launch that Windows process.
- **No real Gemini**, no new real subtitle POST, no TV automatically showing
  this newly generated VI, and no merge claimed by this Draft.

The next integration work item is exactly ONE event edge from the already
trusted TorrServer/OMP selected-media identity to this local factory, using
the existing P4/D3 signed-media identity, not another standalone Windows
helper or manual input sequence. Keep media/session binding and TV
publication as separate evidence gates.
