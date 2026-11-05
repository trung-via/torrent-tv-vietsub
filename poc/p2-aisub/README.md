# P2-AISUB.1 — Offline timed-cue preparation and translation QA

**Current feature:** parse/validate UTF-8 SRT or WebVTT, import a *separately prepared* Vietnamese translation map keyed by cue number, preserve every original cue's millisecond start/end, render SRT/VTT, and refuse missing/extra cues and unsafe markup. Two original synthetic fixture examples are in unit tests.

**Not yet implemented:** AI inference/model translation, ASR, voice-over, provider consent/selection, remote media upload, subtitle download, GPU resource measurement, OMP UI integration or on-TV test. These are separate acceptance gates; this step is the deterministic data contract needed before any model-generated Vietsub.

Example: with `source.srt` containing exactly two cues and locally prepared `vi.json`:

```json
{"1":"Xin chào","2":"Hẹn gặp lại"}
```

```powershell
python poc/p2-aisub/cue_pipeline.py --input source.srt --translations vi.json --output output.vi.srt --confirm LOCAL_OFFLINE_ONE_FILE
```

The command rejects an existing destination, refuses writes to the input/translation file, emits only a cue count (no private caption text), and requires explicit one-file confirmation. No network call and no media processing are performed. The output may be imported with the previously accepted G1 SRT/VTT picker, but this PR does **not** claim the output was tested on Redmi TV.

Limits: 1 MB per input/translation JSON, 2000 cues, strict SRT 1..N sequence, WebVTT header required, cue timestamps valid and ordered, no STYLE/REGION/NOTE preservation in this first slice, plain translated text only (no HTML/WebVTT markup). Failing formats must be fixed explicitly rather than silently dropped. It normalizes cue timestamp spelling while preserving millisecond values; VTT cue identifiers and timing settings remain.

**Test:** `python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -v`.

**Next step:** optional local translator receives cue index/text only after separately approved data rights/provider selection; never overwrite timing, never hallucinate missing cues; compare generated Vietnamese against QA gate and then verify selected media binding in OMP.
