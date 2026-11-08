# P2-AISUB v2c — Continuity-Aware Translation QA (original synthetic only)

**Scope:** Offline **read-only** comparison of explicitly annotated pronouns against scene-effective v2b rules, plus *manually drafted* candidate readability on original SRT/VTT timestamps. **No automatic language understanding or subtitle rewriting.** v2c is not a Gemini/Antigravity backend, a full-film agent memory, or a Redmi TV feature.

## Why this is different from v2a/v2b

- **v2a:** pins source SHA and authored cast, turns, directed `self/other` terms; prevents cross-scene context bleed.
- **v2b:** adds scene-ordered alias and pronoun change *events*, with source + original context digest, no retroactive rewrite. Synthetic Linh/Minh fixture declares an imaginary pronoun change `em/anh` → `tôi/anh` for Linh from scene 2; this is not inferred from any source subtitle.
- **v2c:** compares an annotation of the observed pronouns **provided by a human**, not NLP-guessed words in the Vietnamese text. If the human explicitly marks `em` in scene 2 when v2b expects `tôi`, the system raises `SELF_PRONOUN_MISMATCH_REVIEW`. A null/omitted term is not a mismatch: `unchecked` and `omitted` have different warnings, but no semantic PASS.
- **Timing:** the same fixture cue 7 has a deliberately overlong, originally authored Vietnamese test translation in `fixtures/context_review_v2c_translations.json`. Candidate text is **typed by the human**. Only character count/CPS/CPL/line count are checked, using the exact original timed cue. **No shortening generated** and no automatically applied changes. Even `candidate_meaning_reviewed=true` is an unverified annotation, not a machine-certified meaning or Human benchmark score.

## Contracts and guardrails

The template is strictly bound to canonical source SHA256 (CRLF→LF, preserving other bytes), canonical v2a manifest SHA, v2b event journal SHA, and the SHA of all cue-indexed Vietnamese translations. A changed source/timecode, cast relationship, event note, or a single translation invalidates a previously generated review form. A new form is necessary; old responses are never silently reused.

There are exactly as many `rows` as source cues; each row's `id` must appear in source order. Every row contains:

```json
{
  "id": 7,
  "self_use": {"status": "unchecked", "term": null},
  "other_use": {"status": "unchecked", "term": null},
  "candidate_vi": null,
  "candidate_meaning_reviewed": null
}
```

For each role choose `unchecked` (not yet inspected), `omitted` (that grammatical reference was not explicit) or `explicit` (human actually saw that word/phrase in the text) and, **only** for `explicit`, fill `term`. Do not claim a pronoun is there just because it is expected by the v2b memory. The machine **does not independently confirm that the declared word appears in the raw text**; it only checks the human annotation against the rule. The complete `candidate_vi` may be edited locally for review; it is never translated, auto-rewritten, substituted into the original map or emitted as a new SRT/VTT file. `candidate_meaning_reviewed` may be `null`, `false` or `true`; none is a certificate.

**Security/evidence:** all files remain local to Windows. The private review form may include a manually written alternative, but stdout/report contains **IDs, numeric metrics and warning codes only** (plus content hashes), not actual dialogue, filenames, character names, private user info or arbitrary notes. UTF-8 and CP437 safeguards apply. The CLI checks `original_synthetic` only and requires explicit confirmation to create a **new** review file. No other IO/network or action on TV/Windows services.

## Windows PowerShell — prepare blank review template

Use main after PR merge (pinned commit provided by the merge report):

```powershell
$ErrorActionPreference = "Stop"

$tool = "poc/p2-aisub/context_review_v2c.py"
$source = "poc/p2-aisub/fixtures/agy_scene12_en.srt"
$context = "poc/p2-aisub/fixtures/context_v2_synthetic.json"
$memory = "poc/p2-aisub/fixtures/context_memory_v2b_synthetic.json"
$translationMap = "poc/p2-aisub/fixtures/context_review_v2c_translations.json"

$review = Join-Path $env:TEMP (
    "context-v2c-review-" + (Get-Date -Format "yyyyMMddHHmmssfff") + ".json"
)
python $tool prepare `
    --input $source `
    --context $context `
    --memory $memory `
    --translations $translationMap `
    --out $review `
    --confirm PREPARE_ORIGINAL_SYNTHETIC_REVIEW_V2C

if ($LASTEXITCODE -ne 0) { throw "CONTEXT_V2C_PREPARE_FAILED" }
```

Expected: `CONTEXT_V2C_REVIEW_TEMPLATE_PREPARED cues=12 human_fields_unchecked no_model_call`. This is **not** scored or a translation-quality PASS; all 24 pronoun observation fields remain unchecked.

To inspect the **blank** template (no Human annotation score inferred):

```powershell
python $tool inspect `
    --input $source `
    --context $context `
    --memory $memory `
    --translations $translationMap `
    --review $review

if ($LASTEXITCODE -ne 0) { throw "CONTEXT_V2C_INSPECT_FAILED" }
```

The result is JSON with `explicit_pronoun_mismatch_cues=0` **because none has yet been inspected**, `unchecked_pronoun_fields=24`, `human_semantic_review=REQUIRED`, `quality_certified=false`. It can still warn `READING_SPEED` for the deliberately long synthetic cue 7.

For a targeted **Human-attended** test, open the local review JSON and mark row ID 7 as `self_use.status="explicit"`, `self_use.term="em"`. This should raise `SELF_PRONOUN_MISMATCH_REVIEW` because the fictional v2b event expects `tôi` in scene 2. Optionally set `candidate_vi` to your own shorter Vietnamese alternative and inspect its CPS; **do not** treat a shorter text as preserving English meaning without reviewing the source text. No GitHub upload of filled review form is needed.

## CI, permissions and next steps

Source-only CI tests cover exact hash/IDs, CRLF/Windows, SRT/VTT, missing/new/duplicate rows, changed translations/events, pronoun mismatch and reversed direction, omitted/unchecked, candidate overflow, missing semantic review, local file non-overwrite and redacted stdout. **No real film is examined**, no paid provider quota is consumed, and no Android APK/Redmi result is asserted.

Future v2d may build an optional explicitly approved human review UX and persistent decisions, plus model-assisted proposals only after a separate privacy/rights/cost/consent gate. P2-AISUB issue #60 remains open. The original 36-case benchmark Issue #67 remains 0/36 Human-scored and is not modified by this source work.
