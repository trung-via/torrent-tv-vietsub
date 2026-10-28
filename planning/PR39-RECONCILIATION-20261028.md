# PR39 — Reconciliation and review ledger (2026-10-28)

Scope: review of live GitHub PRs and preserved human/CI evidence; docs-only changes on PR #39. NO merge, dispatch, release, host or TV changes.

Main SHA at review: 55e8afae1d94ffbe0e2baaa35c3cd4b474ce5ed5. PR39 is Draft, GitHub mergeable=true/clean, but its head has no CI checks or reviews. Git-clean is not proof of semantic compatibility.

## Interactions with other Draft PRs

| PR | Observed status | Reconciliation |
| --- | --- | --- |
| [#9](https://github.com/trung-via/torrent-tv-vietsub/pull/9) | ADR-0004 on-demand Vietsub P2 Human-approved goal, unmerged. Contract/PRD/Roadmap overlap PR39. | Preserve P2-AISUB offline translate timed cues first, ASR fallback; P2-SOURCE is separate search; P4 is later OMP integration. Do not overwrite AIOS-independent Contract with old clauses when merging #9. |
| [#15](https://github.com/trung-via/torrent-tv-vietsub/pull/15) | P1 AC-01..08, G0–G4; font-weight/style deferred. Contract and ADR-0006 overlap PR39. | Preserve criteria, do not interpret G0 debug as G1 outside-APK. Review semantic content before rebase/merge. |
| [#11](https://github.com/trung-via/torrent-tv-vietsub/pull/11) | G0 debug source candidate; no direct PR39 file overlap. | No G1 or production claim from G0. |
| [#29–#36](https://github.com/trung-via/torrent-tv-vietsub/pull/36) | Stacked G1d/G4 Drafts; no direct PR39 path overlap. | No auto flatten/rebase/merge; old unsigned G4 audit not product Release proof. |
| [#37](https://github.com/trung-via/torrent-tv-vietsub/pull/37#issuecomment-6444479305) | Human-run Windows TorrServer → Redmi OMP smoke PASS (video/audio, D-pad/seek/reopen), limited fixture and setup. | Keep P0 smoke PASS; not full G-TV firmware/codec or G-SERVER version/auth/Range. Avoid duplicate test unless environment changes. |
| [#38](https://github.com/trung-via/torrent-tv-vietsub/pull/38#issuecomment-6472981972) | [Actions run #40533478080](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/40533478080) Debug+unit SUCCESS. Real Redmi G1-SUB-01: saved SRT selected in UI but not auto-render on reopen, needs manual re-selection. Speed G1-PLAY-01 UNCONFIRMED. | G1 Production remains blocked, no release. Repair late-external-track re-selection with regression proof in PR38, then separately authorized build and TV acceptance. Do not add rate reset on speculation. |

## Merge and execution guidance

1. PR39 may be reviewed and merged as documentation independently if Human explicitly approves, after final docs consistency and branch checks. This review did not merge.
2. Before integrating #9/#15, rebase/cherry-pick narrowly and preserve Human feature and P1 acceptance decisions without restoring obsolete AIOS canonical or new Kotlin+Compose app assumptions.
3. Repair G1-SUB-01 only within PR38 source scope after explicit engineering approval; don't rerun already-passed P0 / 5 negative SRT tests just to collect more logs.
4. Plugin torrent-tv-engineering-flow v0.1 still embeds deprecated AIOS authoring/admission and Kotlin+Compose-first wording. That skill is stale against explicit Human decisions. Plugin update is a separate reviewed scope; current live Contract/ADR outrank dated plugin snapshots.

Unverified: full P1 production release, comprehensive TorrServer API/firmware/codec, AI agent, batch/rolling dubbing and MCP tunnel actual access.