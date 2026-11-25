# TR18 readout findings — 2026-11-25

Scope: research only; no provider invocation, production change or permission expansion.

Owner supplied a private TR19 reader export on 2026-11-25. The source stream digest reported by that export is 3acbc427a56a102bfcd87ac2b5876771002fd43068bf5a8f6180a4cfc72c40f8. The raw stream remains on Windows. Do not publish private logs or subtitle contents.

## Observations

- 74 parsed events, zero invalid lines; 1 init, 72 step_update, 1 result.
- NO_FINAL_TEXT; zero nonempty final_responses and assistant_fragments in supported schema.
- 9 read_file outcomes, 1 list_pages, 12 evaluate_script, 1 denied list_network_requests (23 tool outcomes including non-browser operations).
- Line 71: explicit TOOL_ERROR, permission denied for ttv-browser/list_network_requests.
- CLI stderr confirms headless mode could not prompt for required MCP permission and produced no output. Do not perform the denied operation or attempt to bypass denial.
- Result usage: input_tokens 56913, output_tokens 12607, thinking_tokens 7885, cache_read_tokens 419657, total_tokens 69520. Do not add cache and thinking fields to total without accounting semantics.
- TR18 previously verified one downloaded artifact, 1670 cues, download at 219s, elapsed 235s. No exact release or playback sync proof.

## Decision

TR19A offline reader verified with actual owner-provided export. TR19B automatic private transport remains incomplete; manual private upload succeeded.
TR20 identifies the immediate failure as an unnecessary post-download denied browser operation causing no final report in headless mode.
Teacher recovery requires a separate report-only analysis using existing evidence, with no network inspection or re-download, no broadened permissions.
Do not infer the actual detailed candidate selection rationale from the typed trace. The original Teacher final response is absent in supported fields.
The stream schema also has step_index, duration_seconds and step usage fields; later telemetry can preserve these values for quantitative latency analysis. Do not export internal thought content.

Next gate: receive actual Neon High report and validate the complete Recipe V5 with teacher_report_validator.py before a blind Hydrogen Low exercise. The proposed 60s acquisition target remains an experiment target.
