# ADR-0008 — Research-aligned AI Entertainment Agent on OMP

**Date:** 2026-10-28
**Status:** PROPOSED_FOR_HUMAN_REVIEW / DOCUMENTATION_ONLY
**Reference:** docs/RESEARCH_ALIGNMENT_2026-10-28.md and user-provided completed Deep Research report.
**Precedence:** explicit Human OMP-first and independent-AIOS decisions (ADR-0002, ADR-0007) override report technology preferences.

## Context

The research proposes ChatGPT -> Home Media Gateway -> Discovery/Verification -> TorrServer -> Redmi TV plus Vietnamese Audio Worker. It also recommends building a new native Kotlin/Media3 TV app, **which conflicts with the latest Human decision**. OMP is the product baseline and already includes native player integration. Research findings are not proof of deployment.

## Decision proposed for review (NOT a grant to implement)

1. Preserve OMP Preact/Capacitor UI and existing 2160/Media3/VLC Kotlin player; adapt session/control and vi audio selection in these OMP components after feasibility checks. Never rebuild the entire TV app on Kotlin + Compose.
2. Keep manual magnet and OMP lawful website/source search. Optional Prowlarr/Torznab, Jackett fallback, Candidate Verifier and Home Media Gateway are new modular components on Windows/NAS; no AIOS runtime.
3. Gateway is control-plane owner: policy, auth, session FSM, allowed sources, verification, user confirmation, idempotency, recovery, device status. TorrServer remains independent media-plane engine, not bundled or forked.
4. Verify seeder provenance (reported/scraped/connected), exact pixel policy, media probe and measured stream readiness. Prefer direct HTTP, remux then transcode only when deployed build/hardware need it.
5. Prioritize existing vi-VN tracks and external Vietsub. AI voice-over must be rights-cleared opt-in with multilingual ASR/MT/TTS timing/mix; **batch before rolling**, no live-dubbing claim.
6. ChatGPT may use narrow semantic MCP via Gateway after a security/official-connectivity gate; never expose raw TorrServer /mcp/admin or open inbound WAN ports. TV control requires real Redmi capabilities/pairing.
7. Keep explicit cloud processing consent, licensing, source-rights review, provenance, secret isolation and release approval. Test/review individually; no automatic runner/host/TV modification.

## Consequences

- Report's new native player timeline/effort does not directly apply to OMP-first. Its proposed 6–10-week/54–103-person-day POC is not a project commitment.
- Gates are G-OMP, G-SERVER, G-TV, G-P1, G-VERIFY, G-GATEWAY, G-AGENT, G-AUDIO-BATCH, G-ROLLING and G-MCP, with independent evidence.
- This ADR is a **DRAFT proposal**, not an accepted implementation mandate; only existing Human-decided OMP/AIOS boundaries are binding.
- Retain other Draft PRs. Do not merge PR #39, run workflows, install Prowlarr, open network ports, launch AI processing, or change source code under this docs update.

## Rollback

Revert proposed docs via reviewed PR; preserve historical ADRs and existing OMP-first authority.
