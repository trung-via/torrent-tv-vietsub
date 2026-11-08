# P2-AISUB Context Memory v2b — continuity across explicitly authored scenes

**Status:** Source-only original-fiction PoC. No Gemini/Antigravity calls, AI memory extraction, real films, diarization, actor identity inference, subtitle generation, local-service changes, OMP player or Redmi TV effects.

## Why v2b exists

The already-completed original synthetic 36/36 context benchmark (Issue #67) has strict **JSON import PASS**, but **0/36 human-scored** semantic ratings. In editorial review, pronouns, formal titles and referents were sometimes guesses. Previous v2a (Issue #69; Windows CRLF fix #71) pins a source SHA and explicitly authored scene/character relations, but its pronouns are static across scenes. v2b adds a deterministic timeline of **explicit, manually supplied events**. It is not able to deduce that a character's relationship changed just by reading the dialogue; the events are untrusted source data with claimed authorship, not independently verified Human signoff.

### Contracts

- Existing original `agy_scene12_en.srt` and `context_v2_synthetic.json` remain untouched. The first and second synthetic scene in that manifest provide cue ranges 1–6 and 7–12.
- New `fixtures/context_memory_v2b_synthetic.json` has exact `schema, provenance, source_sha256, base_context_sha256, events`. The source hash is the **canonical CRLF→LF SHA256** from v2a, preserving the Windows runtime repair. The base-context hash is SHA256 of sorted-key, compact **canonical JSON**. Changing the authored cast, roles, turns, scene boundaries, notes or anything else in the base metadata invalidates that event journal.
- Each event has stable `id, scene_id, kind, evidence, note`, plus kind-specific data. Events must be ordered by scene, reference **only existing** scenes and characters, have no duplicate event IDs or same-scene conflicting keys, and carry `fixture_authored` or `human_reviewed` evidence. For any non-fictional (human-supplied) metadata, only `human_reviewed` is an acceptable **typed declaration**; this code cannot prove a person actually reviewed it.
- `alias_confirmed` associates an NFC nickname with one character starting **at the specified scene**. Canonical character names and any prior nickname (including revoked aliases) are reserved to avoid rebinding one name to another character. `alias_revoked` removes a **previously active** alias only from that scene onward. No guessing actor gender, relationship or alias from language.
- `address_confirmed` updates the directed `speaker -> addressee` tuple (`self` / `other` pronouns) at the start of its scene. The reverse direction never changes implicitly. Same-scene duplicate direction or no-op "updates" fail. Unconfirmed directed pairs remain `UNCONFIRMED_PRONOUN_PAIR`.
- Events at scene N **never rewrite** previously emitted scenes or leak into N-1. Target cues remain disjoint in chunks ≤12 per scene. Neighbor cue context is read-only and remains within the same scene, inherited from v2a. Model prompts, if ever separately approved, must treat event metadata as **untrusted DATA**, not control instructions.

### Synthetic example — illustrates replay, NOT truth from the dialogue

In the **original fictional** Linh/Minh scene, one `fixture_authored` event makes a nickname `Mây` effective in `station_reunion`; a second event explicitly **imagines** Linh switching from `em/anh` to distant `tôi/anh` at the start of `station_decision`. The original spoken English does **not** independently prove this nickname or switch! They are test-only conditions designed to verify memory behavior. Minh→Linh stays `anh/em` until separately changed.

No user's actual relationship or private media is represented. A different source digest, modified underlying context, conflicting alias or event metadata is rejected before creating a plan. v2b creates a **new local plan** only after explicit confirmation; it cannot edit the original subtitle or make a model call.

## Windows PowerShell test (offline, no tokens)

Run from `trung-via/torrent-tv-vietsub` pinned at the commit containing this PR (once merged), then:

```powershell
$ErrorActionPreference = "Stop"
$tool = "poc/p2-aisub/context_memory_v2b.py"
$source = "poc/p2-aisub/fixtures/agy_scene12_en.srt"
$context = "poc/p2-aisub/fixtures/context_v2_synthetic.json"
$memory = "poc/p2-aisub/fixtures/context_memory_v2b_synthetic.json"

$plan = Join-Path $env:TEMP (
    "context-v2b-" + (Get-Date -Format "yyyyMMddHHmmssfff") + ".json"
)

python $tool prepare `
    --input $source `
    --context $context `
    --memory $memory `
    --out $plan `
    --confirm PREPARE_ORIGINAL_SYNTHETIC_MEMORY_V2B

if ($LASTEXITCODE -ne 0) { throw "CONTEXT_V2B_PREPARE_FAILED" }
```

Expected one output line:

```text
CONTEXT_V2B_PLAN_PREPARED scenes=2 cues=12 events=2 no_model_call
```

The local `$plan` JSON contains a 2-scene event replay, source timestamps, `continuity_authority` attached to every addressed target, and current `confirmed_aliases_untrusted`. At cue 1, Linh→Minh still reads `em/anh` (from v2a); cue 7 switches to `tôi/anh` (fictional authored v2b event). This checks code correctness, not correctness of an AI translation.

**Optional read-only QA** (only if you already have a manually prepared 12-item cue-ID → Vietnamese-text JSON map, **not** the old SRT or 36-case CLI response envelope):

```powershell
python $tool inspect `
    --input $source `
    --context $context `
    --memory $memory `
    --translations $localTranslationMap
```

This uses the existing `cue_pipeline.py` and `subtitle_quality.py`: validates all 12 translations, strict Unicode/CP437, reports actual subtitle timings, CPS/CPL/line-limit flags and unresolved continuity warnings. Standard output contains only numeric/ID warnings, no source dialogue, names, paths or provider/session data. The tool cannot certify a natural Vietnamese voice, sarcasm or whether a model chose the *approved pronouns* inside arbitrary free-form Vietnamese. All semantic and identity acceptance remains Human.

## Independent acceptance and next work

- Unit CI tests validate exact event journals, alias/role collision, no future-event contamination, reproducible replay, source/context SHA drift, Windows LF/CRLF, SRT/VTT, missing translations, non-overwrite and no network/provider/API effects. Separate Human Windows prepare receipt is required to mark real Windows PASS.
- This is intentionally **not an automatic feature within the Android TV app**. Genuine full-film persistent speaker memory requires actual rights/consent, stable film/episode source identifier, timed speaker turns from validated diarization or human annotations, alias confirmation interactions, status persistence and corrections with provenance. Real-media/TV acceptance will be independent of this code CI.
- The 36-case Human scoring sheets from v1 remain untouched and unscored. No results, quality score or real-model token usage were fabricated here.
