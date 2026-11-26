# G1 Brain Training — native AGY discovery

Decision: Owner approved training and changed G1 acceptance to <=150s first visible Vietsub on Redmi. Source baseline `83fba113a0341edece327b2f8f92e6078d3094e2`, recipe V13.1, verifier V13.1-BR05-1, AGY Hydrogen Low. Scope: normal authorized browser path only; no extra acquisition or provider call for the historical Resident Evil sample.

## BT0: Baseline and budget

Resident Evil run 45863284122: 15s preparation, 130s AGY start to EN verified, 46s first 50 cues, 221s remaining, 412s full 1,021 cues. First checkpoint 191s, not a TV-render measurement. Proposed initial budget: tap+ingress+preparation <=15s; EN acquisition <=75s; first 50 cues <=50s; P4/render <=10s. Sum 150s; these are allocation targets, not measurements. Optimize acquisition first: saving at least 41s to reach 150s even before TV delivery. Actual target saving must include tap/P4 overhead.

## BT1: Teacher evidence

Use existing successful Resident Evil proof, no replay. Count actual browser tool outcomes, repeated reads, inspected details, English candidate rows, CLI stream duration and post-CLI retention interval. HostOps read-only source commit 60b0e68f436ddec2a6f7ef37060cdb88592cdf93, dispatch comment 7198433466. Raw private evidence stays local. The existing verifier independently establishes artifact, selected candidate and valid SRT; user reports real visible cue. Exact synchronization has not been measured across playback.

## BT2-BT6: Transfer and independent evaluation

Candidate should consolidate observed page/control reads; navigate to ordinary search once; use dynamic title/year and verified English filter; collect actual English rows/coverage and selected candidate-specific detail; choose correct cut rather than encoding label; inspect other detail only when it could change selection; ordinary Download once after binding selected detail; stop tools after click and return compact evidence. Do not use known candidate IDs, cache, guessed URLs, or change acceptance semantics. Preserve unknown metadata and explicit runtime conflicts; do not bypass site restrictions. The recipe is not adopted merely because it is shorter. Keep the prior version available. Next distinct naturally authorized film is the Student test. Record exact loaded recipe, cold source cache status, timing and artifact acceptance. No model-weight training, no new service, no repeated paid test. Compare with Resident Evil as a historical reference, not a matched A/B trial; multiple distinct films needed for a generalization claim. If candidate is slower or mismatched retain baseline and diagnose. Real visible cue <=150s remains independent product gate.

Status: BT0 baseline verified; BT1 evidence extraction dispatched; BT2 candidate principles recorded; BT3-BT6 not yet live verified.

## BT1 readout — 2026-11-27 ICT

[HostOps 45864378688](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/45864378688), successful Owner receipt: R_BT_RE_O11L1N3S0E7C0F0K0W0D0R6I1_CLI123_POST7. Resident Evil: 11 observed MCP outcomes (1 list_pages, 3 navigate_page, 7 evaluate_script), zero byte-identical repeat reads among the observed output payloads, 6 English candidates, 1 inspected candidate detail. CLI stream elapsed approximately 123s, post-CLI retained ZIP write approximately 7s. These file timestamps do not isolate model inference, Chrome network latency, browser tool durations or the download-completion moment. This evidence does not support blaming exhaustive pagination or repeated identical reads for the 130s. Prioritize lower overhead in the actual CLI/recipe path; do not remove the independent verifier.

## BT2 candidate recipe: V13.2-compact (DESIGN_ONLY, not loaded)

Objective: produce one candidate-bound English SRT for the exact film and plausible cut using the authorized OpenSubtitles.org tab; minimize decision/report overhead. Input: dynamic film title/year, release hints, measured runtime/FPS. Unknown means unknown. No known answers or fixture IDs. Use only the existing ttv-browser tools and ordinary UI. Every page action uses numeric pageId. No API, alternate provider, access bypass or guessing URLs.

1. List the authorized task tab once. Start from the ordinary search page. In one bounded DOM read identify actual search/filter controls. Submit title/year. Use the visible English filter if needed. Verify actual English result URL and heading.
2. Per actual result page, collect the existing verifier's required compact JSON: url, heading, page_title (actual document.title), total_english, count_scope, count_label, has_next, next_href, rows (href, lang, title, release, fps, badges, release_group, hi). Count only the scoped English result count; follow genuine same-result pagination until coverage is established. Never invent missing metadata.
3. Rank the six or other observed rows locally, prioritizing correct movie/year/cut, runtime compatibility, completeness and evidence over encoding labels. Inspect the strongest candidate detail via one compact DOM query: url, candidate_id, title, btnVisible, fieldsetText, downloadHref, downloaderChecked. Inspect another only when material ambiguity could change the choice. Nominal FPS or encoding differences alone do not prove drift. Explicit cut/runtime conflict is disqualifying.
4. In one final bounded evaluate_script, verify selected detail ID, visible ordinary Download href, and optional downloader checkbox unchecked/absent. Use ordinary UI to uncheck if necessary; click once only. Emit {clicked:true,pageUrl,href,id,downloaderChecked}; stop browser actions. Host owns file verification, English/SRT checks and durable storage. On uncertainty or denied access stop, no bypass or alternate route.
5. Return only compact status, observed evidence, release_match, material compatibility_uncertainties, action/recipe codes, failures, improvements and usage if exposed in the existing contract. Avoid duplicating DOM observations or narrating routine steps. Never claim a downloaded file from click alone. Keep actual evidence fields needed by the current verifier; shorter report is not permission to omit them.

Candidate goals: <=8 observed outcomes where possible without skipping necessary controls, <=75s from provider start to verified EN. A tool count is a diagnostic, not a hard stop. Measure a new cold film, exact recipe loaded, independent EN artifact receipt and same-film rendered cue. Do not replay Resident Evil. Do not change model, LEAN120 size, verifier or production configuration merely to promote this candidate.

Status: BT1 retained live teacher case verified; BT2 candidate written, untested. BT3/BT4 Student live comparison and BT6 adoption pending authorization for recipe deployment and a distinct cold film; no runtime effect claimed.

## BT3 source candidate

Owner approved continuation into V13.2 Compact. Source uses the shorter prompt by default, retains V13.1 prompt for rollback, preserves VERIFICATION_REVISION V13.1-BR05-1 and all existing evidence checks. No change to model, CLI transport, translation windows, or cache format. Next fresh film only; no replay of Resident Evil. Offline checks prove contract compatibility, not measured latency. Deployment and Student benchmark require their own receipts.

## FLAT verifier audit — 2026-11-27 ICT

Owner approved removing search-method gates while preserving correct English source, candidate-bound original ZIP and real timeline checks. V13.2 Student failed at 120s, provider start 8s, actual artifact/evidence retained (45867567291). V13.3 installed but rejected selected-candidate binding (45868278484). Exact retained audit 45906822714 R_AUDIT_O10J14_R1L0B1M1_D1V1H1F1_C1H1K1Q1_N3381_G0: selected row/release/movie, detail, ordinary click, artifact ID, order and valid SRT all observed; row language not recognized. Second audit 45907044376 R_LANG_EMMM_DMMF0X0T1S1_P1U1H1Y1_C45_R1O0_L10158D10463: blank row language, actual English-filtered list URL/heading/title, selected detail English title and -en slug, 3,381 cues, last cue 10,158s <= 10,463s film duration; no explicit runtime conflict. English-content heuristic is supporting only. V13.4-BR07-1 accepts blank language only with corroborating filtered result and selected detail, rejects explicit conflicts, preserves all original identity/artifact/timeline checks; row/detail order before click is not a prescribed search method. Coverage metrics remain observational. No new download; revalidate retained bytes and use existing requeue only if accepted. No sync/latency PASS from this recovered case.
