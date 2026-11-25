# TR18 Teacher recovery checkpoint

Date: 2026-11-25
Scope: G1.2 research, not production deployment.

## Observed evidence

| Run | Model | Provider | Total seconds | Download seconds | Browser outcomes | Cues |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 45531978582 | Hydrogen Low | SubtitleCat | 122 | 109 | 10 | 1672 |
| 45534073456 | Hydrogen Low | OpenSubtitles | 133 | 123 | 9 | 1670 |
| 45535079273 | Neon High | OpenSubtitles | 235 | 219 | 14 | 1670 |

TR18 had title/language binding evidence, no verified exact release or playback sync.
TR18-R run 45535927975 inspected all 74 stream events: no invalid JSON, exit 0,
one empty final response, explicit permission error at event 70 after download,
no Recipe V5 artifact. The exact rejected operation is not identified.
The readout is a typed projection, not the raw private log.

## Verified validator

Source commit 6715a3668f5b54769363a844bf656ec5baf61cd8.
Git blob d10a45bbd10031a5f3e66a4cb8dbfd586cddb35a.
All nine tests in teacher_report_validator.py ran successfully in an independent
local Python environment on 2026-11-25. No CI or Windows runtime acceptance implied.

## Recovery contract

Do not repeat the completed download. Use a normal supported Neon High report-only
session to analyze the observed evidence and produce a reusable Recipe V5 and student
exercise. No browser, file or shell actions are required for the report-only task.
The model must return an inline JSON object with status REPORT_READY, nonempty
recipe_v5, diagnosis, demonstration_steps, student_exercise, grading_rubric,
latency_experiment, limitations, observed_evidence, and an integer
acquisition_budget_seconds. The 60-second acquisition goal is a proposed budget,
not an observed result. G1 end-to-end remains 120 seconds to a visible Vietnamese
cue on Redmi.

Run the validator against the actual final response and observed exit/permission
state before any recipe handoff. REPORT_READY_FOR_BRAIN_REVIEW is not Brain PASS.
Then inspect factual claims, privacy, release evidence, and transferability.
A separate blind Student exercise is needed before adoption.

## Current blockers

The earlier Teacher report-only job write was blocked by the tool safety check.
No such job was dispatched. Do not retry or route around the blocked operation.
No supported direct Neon High connector was found. A genuine Teacher response
remains necessary. Validator is standalone and not wired into the Windows runtime.
Keep the existing HostOps branch at cc1988013e43634235a719dc27dbb3135e55b656
unless a separately authorized and supported change is verified.

No production restart, TV deployment, merge, provider retry, or training PASS
is authorized or implied by this checkpoint.
