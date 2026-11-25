"""TR19: offline reader of AGY stream JSON, without provider or network calls.
Output is private. Review before sharing. No automatic upload.
"""
import argparse
import hashlib
import json
from pathlib import Path


def extract(stream, stderr=""):
    records, invalid, messages, tools, errors, usage, unknown = [], [], [], [], [], [], []
    finals = []
    for index, line in enumerate(stream.splitlines(), 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                raise ValueError("not an object")
        except ValueError:
            invalid.append(index)
            continue
        records.append(event)
        kind = event.get("event")
        result = event.get("result")
        if kind == "result" and isinstance(result, dict):
            # Only confirmed public response field is authoritative.
            response = result.get("response")
            if isinstance(response, str) and response.strip():
                finals.append(response)
            if result.get("error"):
                errors.append({"line": index, "error": result["error"]})
            if isinstance(result.get("usage"), dict):
                usage.append({"line": index, "usage": result["usage"]})
        # Explicit assistant messages, kept as fragments, never guessed as final.
        # Do not extract thought/reasoning fields or arbitrary nested strings.
        if kind == "message" and event.get("role") == "assistant":
            value = event.get("content")
            if isinstance(value, str) and value.strip():
                messages.append({"line": index, "text": value})
            elif isinstance(value, list):
                for block in value:
                    if isinstance(block, dict) and block.get("type") in ("text", "output_text") and isinstance(block.get("text"), str):
                        messages.append({"line": index, "text": block["text"]})
        if kind == "content_block_delta":
            delta = event.get("delta")
            if isinstance(delta, dict) and delta.get("type") == "text_delta" and isinstance(delta.get("text"), str):
                messages.append({"line": index, "text": delta["text"]})
        step = event.get("step_update")
        if isinstance(step, dict):
            info = step.get("tool_info")
            if isinstance(info, dict):
                params = info.get("parameters")
                name = step.get("tool_name")
                if name == "call_mcp_tool" and isinstance(params, dict):
                    name = params.get("ToolName", name)
                # Only operation name and outcome; raw page output stays in source.
                if "output" in info or "error" in info:
                    tools.append({"line": index, "tool": name, "has_output": "output" in info, "has_error": bool(info.get("error"))})
                if info.get("error"):
                    errors.append({"line": index, "error": info["error"]})
            if step.get("error"):
                errors.append({"line": index, "error": step["error"]})
        if event.get("error"):
            errors.append({"line": index, "error": event["error"]})
        if isinstance(event.get("usage"), dict):
            usage.append({"line": index, "usage": event["usage"]})
        # Field names only, so unfamiliar schemas can be investigated without exposing content.
        unknown.append({"line": index, "event": kind, "keys": sorted(event),
                        "step_keys": sorted(step) if isinstance(step, dict) else [],
                        "result_keys": sorted(result) if isinstance(result, dict) else []})
    final_status = "FINAL_PRESENT" if finals else ("PARTIAL_TEXT_ONLY" if messages else "NO_FINAL_TEXT")
    return {"schema": "TTV-AGY-PRIVATE-READOUT-V1", "status": final_status,
            "stream_sha256": hashlib.sha256(stream.encode("utf-8")).hexdigest(),
            "events": len(records), "invalid_lines": invalid,
            "final_responses": finals, "assistant_fragments": messages,
            "tool_outcomes": tools, "errors": errors, "stderr": stderr,
            "usage": usage, "event_schema_inventory": unknown,
            "note": "Private diagnostic output. Not a training PASS. Unknown event schemas may contain additional content. Review before sharing."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stream", type=Path)
    parser.add_argument("--stderr", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve() in {args.stream.resolve(), args.stderr.resolve() if args.stderr else None}:
        parser.error("output must not overwrite a source log")
    stream = args.stream.read_text(encoding="utf-8-sig", errors="strict")
    stderr = args.stderr.read_text(encoding="utf-8-sig", errors="replace") if args.stderr else ""
    result = extract(stream, stderr)
    with args.output.open("x", encoding="utf-8") as out:
        json.dump(result, out, ensure_ascii=False, indent=2)
        out.write("\n")
    print(result["status"], "events=" + str(result["events"]), "invalid=" + str(len(result["invalid_lines"])))


if __name__ == "__main__":
    main()
