# PR #9 ↔ PR #10 — Reconciliation và desk-review

**Ngày:** 2026-10-25
**Status:** `INTEGRATED_DRAFT / DESK_REVIEW_ONLY / INDEPENDENT_REVIEW_PENDING`
**Human intent:** đồng ý tiếp tục đồng bộ PR #9/#10 và thực hiện review tài liệu trước khi merge; không ủy quyền bỏ qua independent review, AIOS canonical flow hay phát hành APK.

## Immutable inputs

- App `main`: `67b769ce29ce9c166472f97ef46b37170a525e29` tại lần bắt đầu reconciliation.
- PR #10 P1a HEAD before stacking: `9ea049b65356d42c11afffd33d0dd9480d4a1b00`.
- PR #9 original P2 HEAD: `38fe10dabc50ec0b05999d3dfb91ea3b2311410f`.
- OMP pinned source: `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, 2160player gitlink `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`.

## Non-destructive resolution

1. **PR #10 remains a standalone Draft targeting `main`**. It owns P1a source-agnostic scope, ADR-0005 history, ADR-0006, the self-authored SRT fixture, the P1 plan and F-01..F-04.
2. **PR #9 becomes a stacked Draft targeting the PR #10 branch**. The PR #9 branch holds a merge commit with both old PR #9 and PR #10 as parents, preserving ancestry without force-push. Against its new base PR #10, PR #9 should show only P2 AI Vietsub changes plus this note and ADR-0004.
3. Contract/PRD/Roadmap P1 content is **taken verbatim from PR #10** as the conflict-resolution source. P2 content is selectively transplanted from PR #9 with clarification on P1a-G1 dependency, while keeping the feature DECIDED and implementation PROPOSED.
4. **No merge order inversion:** if PR #10 is merged after independent review, PR #9 must be rechecked/rebased to `main` and independently reviewed with currentness before merge. No auto-merge from this planning commit.

## Audit of main intersections

| Surface | Conflict found | Reconciled behavior |
| --- | --- | --- |
| Contract §C1 #9 / §C3 P2 / §C6 AI | Earlier P2 conflated ASR → TTS and lacked G0/G1 distinction | AI Vietsub DECIDED; translate timed text first, then optional ASR. TTS later. TV E2E only if G1 proof exists |
| Contract §C1 #12 / §C6 P1 | PR #9 based on old main would erase P1a source-agnostic/G0/G1 text | Preserve every PR #10 P1a paragraph and acceptance gates |
| PRD §2 / §6 | PR #10 still described P2+TTS in one step | Separate AI subtitle PoC from TTS, keep local opt-in and privacy; no AI service by default |
| Roadmap #2a-0/#2a-1/#5 | PR #9 omitted P1 stages; PR #10 P2 was bundled AI/TTS | Preserve P1a stages, add bounded AI-before-TTS P2 row |
| ADR #4 vs #6 | P2 TV playback could be mistaken as verified after debug fixture G0 | Explicit dependency on full P1a-G1 and undecided P1b transport |

## V1 desk findings closure limits

- **F-01:** G0 debug fixture render is **not** arbitrary file import or `EXTERNAL_SRT_E2E_PASS`; only G1 real device evidence can support P2 TV integration.
- **F-02:** four-cue Unicode SRT is **not** media-synced validation nor track persistence; separate controlled clip and reopen with debug re-injection off.
- **F-03:** debug hook/asset must not appear or activate in release build. No PoC code is included in these docs.
- **F-04:** upstream build/runner smoke are historical and target repo remains docs-first; not accepted fork build/TV/AIOS dispatch.

## Review result and remaining blockers

- Desk-review verified contract/P1 decisions are not overwritten by P2, and P2 precedence/consent/privacy remain intact. **This is not an independent reviewer submission or canonical V1/AIOS verdict.**
- **PENDING:** independent human/reviewer review of both exact PR heads; PR #9 base and diff sanity; GPL/third-party/runner source gate before implementation; no Android code or hardware verification.
- **STOP:** mismatched refs, PR #10 no longer current, unmet review policy, changed Human decision, or P1 findings removed by later patch. Return to audit without merging.

## Merge/rollback

Keep both PRs Draft; close no history and rewrite no published main. Review PR #10 first, then PR #9 as its child. Any future merge occurs only after separate approval + required review and base recheck.
