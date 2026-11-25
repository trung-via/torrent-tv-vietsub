# Brain-led benchmark: retain MCP / CDP 9555

Owner decision, 2026-11-25: retain existing ttv-browser MCP connected to dedicated Chrome CDP loopback port 9555 for all four Brain-led benchmark trials. This supplements BRAIN-LED-BENCHMARK-DECISION.md at f8e8bbbc665efcc814e1aba3d09d989e3573f7b0.

Historical source db9d7d8af8d05556014950745c4666bb038ca799, hostops/laptop-ops/operations/tr-ttv-06-student-v3.ps1, configures chrome-devtools-mcp@1.14.0 with browser URL http://127.0.0.1:9555 and isolated CDP9555Profile. This is source evidence and historical TR18 configuration, not a fresh listener health check.

Use the existing AGY CLI and authorized MCP tool scope; no new browser bridge or port, no use of WakeHub 9444, no permission expansion, no denied network-inspection action or workaround. Normal visible website interaction only; stop browser work after the required acquisition outcome. Host independently verifies the downloaded file. Preserve comparable documented browser/cache state across trials without deleting production data.

Neon High first: SubtitleCat and OpenSubtitles independently. Brain reviews public action summaries and measured telemetry, then Hydrogen Low runs each provider using Brain-optimized recipe. Record actual model, source, tool outcomes, timings, usage, candidate metadata, file validation and translation quality. Missing data remains explicitly unknown.

No live host or provider action performed by this decision. Fresh 9555 runtime readiness and benchmark dispatch remain unverified; prior tool rejection remains unresolved. No production changes.
