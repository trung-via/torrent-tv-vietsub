"""P2-AISUB.2e: attended, resumable Human scoring for original 36-case benchmark.

This terminal helper does not run a model, infer score values, search for media,
or alter the original import, corpus, unscored template or existing score tool.
Private EN/VI dialogue is printed ONLY to an attended local terminal, never to
GitHub, stdout in non-interactive mode, or CI by this CLI.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
from typing import Any

from benchmark36 import (
    SCHEMA_TRANSLATIONS, SCORE_FIELDS, _parse_json, _write_new, batch_cases,
    rating_template, score_review, corpus,
)

CONFIRM = "ATTENDED_HUMAN_SCORE_36"
BIND_SCHEMA = "P2-AISUB.2e-human-draft-binding-v1"


def _load(path: Path) -> Any:
    try:
        return _parse_json(path.read_text(encoding="utf-8-sig"))
    except UnicodeError as exc:
        raise ValueError("HUMAN_SCORE_UTF8_JSON_REQUIRED") from exc


def _stable_digest(data: Any) -> str:
    """Bind exact accepted translation content, ignoring JSON format/CRLF."""
    return hashlib.sha256(
        json.dumps(data, ensure_ascii=False, sort_keys=True,
                   separators=(",", ":"), allow_nan=False).encode("utf-8")
    ).hexdigest()


def _translation_info(translations: Any) -> tuple[int, str, list[dict[str, Any]]]:
    _, sha = corpus()
    if (
        not isinstance(translations, dict)
        or set(translations) != {
            "schema", "corpus_sha256", "batch", "blind_label", "translations",
            "usage", "source", "machine_readability_not_semantic_pass"
        }
        or translations["schema"] != SCHEMA_TRANSLATIONS
        or translations["corpus_sha256"] != sha
        or translations["source"] != "human_attended_cli_receipt"
        or translations["machine_readability_not_semantic_pass"] is not True
    ):
        raise ValueError("HUMAN_SCORE_TRANSLATION_PROVENANCE_INVALID")
    batch = translations["batch"]
    label = translations["blind_label"]
    if type(batch) is not int or batch not in (1, 2, 3):
        raise ValueError("HUMAN_SCORE_BATCH_INVALID")
    # rating_template validates the blind-label schema as well.
    rating_template(batch, label)
    rows = translations["translations"]
    cases = batch_cases(batch)
    if not isinstance(rows, list) or len(rows) != 12:
        raise ValueError("HUMAN_SCORE_TRANSLATION_ROWS_INVALID")
    for row, case in zip(rows, cases):
        if (not isinstance(row, dict) or set(row) != {"id", "vi"}
            or type(row["id"]) is not int or row["id"] != case["id"]
            or not isinstance(row["vi"], str) or not row["vi"].strip()
            or len(row["vi"]) > 1500):
            raise ValueError("HUMAN_SCORE_TRANSLATION_ID_OR_TEXT_INVALID")
        try:
            row["vi"].encode("utf-8", "strict")
        except UnicodeError as exc:
            raise ValueError("HUMAN_SCORE_TRANSLATION_UTF8_INVALID") from exc
    return batch, label, rows


def _draft_status(draft: Any, *, batch: int, label: str) -> int:
    expected = rating_template(batch, label)
    if not isinstance(draft, dict) or set(draft) != set(expected):
        raise ValueError("HUMAN_SCORE_DRAFT_SCHEMA_INVALID")
    for key in expected:
        if key != "ratings" and draft[key] != expected[key]:
            raise ValueError("HUMAN_SCORE_DRAFT_PROVENANCE_INVALID")
    rows = draft["ratings"]
    if not isinstance(rows, list) or len(rows) != 12:
        raise ValueError("HUMAN_SCORE_DRAFT_ROWS_INVALID")
    completed = 0
    for row, blank in zip(rows, expected["ratings"]):
        if (not isinstance(row, dict) or set(row) != set(blank)
            or type(row["id"]) is not int or row["id"] != blank["id"]):
            raise ValueError("HUMAN_SCORE_DRAFT_ID_OR_KEYS_INVALID")
        values = [row[key] for key in SCORE_FIELDS]
        hallucination = row["hallucination"]
        if all(x is None for x in values) and hallucination is None:
            continue
        if (any(type(x) is not int or x < 1 or x > 5 for x in values)
            or type(hallucination) is not bool):
            raise ValueError("HUMAN_SCORE_DRAFT_PARTIAL_OR_INVALID_ENTRY")
        completed += 1
    return completed


def _binding(translations: Any, batch: int, label: str) -> dict[str, Any]:
    _, sha = corpus()
    return {
        "schema": BIND_SCHEMA,
        "corpus_sha256": sha,
        "batch": batch,
        "blind_label": label,
        "translation_sha256": _stable_digest(translations),
        "human_assessment_independence_unverified": True,
        "provider_or_network_call": False,
    }


def _lock_path(out: Path) -> Path:
    return out.with_name(out.name + ".binding.json")


def _dump(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def _open_or_resume(out: Path, translations: Any, template: Any,
                    batch: int, label: str) -> dict[str, Any]:
    """Create a new local draft or validate existing draft+binding; never reset."""
    lock = _lock_path(out)
    if out.resolve() == lock.resolve() or out.is_symlink() or lock.is_symlink():
        raise ValueError("HUMAN_SCORE_UNSAFE_OUTPUT_PATH")
    expected = _binding(translations, batch, label)
    if out.exists() or lock.exists():
        if not out.is_file() or not lock.is_file():
            raise ValueError("HUMAN_SCORE_DRAFT_BINDING_INCOMPLETE")
        if _load(lock) != expected:
            raise ValueError("HUMAN_SCORE_TRANSLATION_CHANGED_REFUSE_RESUME")
        draft = _load(out)
        _draft_status(draft, batch=batch, label=label)
        return draft
    if template != rating_template(batch, label):
        raise ValueError("HUMAN_SCORE_ORIGINAL_BLANK_TEMPLATE_REQUIRED")
    if not out.parent.is_dir():
        raise ValueError("HUMAN_SCORE_OUTPUT_DIRECTORY_REQUIRED")
    # Exclusive creates: do not overwrite any existing user file or template.
    _write_new(out, _dump(template))
    try:
        _write_new(lock, _dump(expected))
    except Exception:
        # Do not remove unrelated data; only clean the just-created blank draft.
        out.unlink()
        raise
    return template


def _checkpoint(out: Path, data: dict[str, Any]) -> None:
    """Atomic replacement of the chosen, previously bound draft after each answer."""
    if not out.is_file() or out.is_symlink() or not _lock_path(out).is_file():
        raise ValueError("HUMAN_SCORE_DRAFT_DISAPPEARED")
    tmp: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", newline="\n",
                dir=out.parent, prefix=".human-score36-", suffix=".tmp",
                delete=False) as f:
            tmp = Path(f.name)
            f.write(_dump(data))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, out)
    finally:
        if tmp is not None and tmp.exists():
            tmp.unlink()


def parse_manual_line(raw: str) -> dict[str, Any]:
    """Six explicit answers, no defaults: five independent scores and y/n."""
    parts = raw.strip().split()
    if (len(parts) != 6
        or any(part not in ("1", "2", "3", "4", "5") for part in parts[:5])
        or parts[5].lower() not in ("y", "n")):
        raise ValueError("HUMAN_SCORE_INPUT_EXPECTED_5_RATINGS_AND_YN")
    return {
        **{name: int(value) for name, value in zip(SCORE_FIELDS, parts[:5])},
        "hallucination": parts[5].lower() == "y",
    }


def mark_case(draft: dict[str, Any], batch: int, label: str, case_id: int,
              entered: str) -> dict[str, Any]:
    """Pure per-case update; used only with explicit attended input in CLI."""
    _draft_status(draft, batch=batch, label=label)
    cases = batch_cases(batch)
    ids = [c["id"] for c in cases]
    if type(case_id) is not int or case_id not in ids:
        raise ValueError("HUMAN_SCORE_ID_OUTSIDE_SELECTED_BATCH")
    index = ids.index(case_id)
    if draft["ratings"][index]["semantic_accuracy"] is not None:
        raise ValueError("HUMAN_SCORE_ALREADY_RECORDED_NO_SILENT_OVERWRITE")
    values = parse_manual_line(entered)
    result = json.loads(_dump(draft))
    result["ratings"][index].update(values)
    _draft_status(result, batch=batch, label=label)
    return result


def _status(batch: int, draft: dict[str, Any], label: str) -> str:
    n = _draft_status(draft, batch=batch, label=label)
    return f"BENCHMARK36_HUMAN_PROGRESS batch={batch} scored={n}/12 remaining={12-n} human_input_only"


def _terminal_score(translations: Any, draft: dict[str, Any], out: Path,
                    batch: int, label: str, selected_id: int | None = None) -> None:
    """Print local source and provider text only with a real interactive terminal."""
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise ValueError("HUMAN_SCORE_INTERACTIVE_TERMINAL_REQUIRED")
    cases = batch_cases(batch)
    rows = translations["translations"]
    print("Năm điểm: nghĩa, tự nhiên, xưng hô, sắc thái, dễ đọc (1–5).")
    print("Kết thúc: y = có bịa thêm ý đáng kể; n = không.")
    print("Nhập một dòng ví dụ '4 5 3 4 2 n'. q = thoát, s = bỏ qua câu.")
    print("Thông tin gốc/bản dịch chỉ hiển thị trong terminal cá nhân này.")
    for idx, (case, row) in enumerate(zip(cases, rows)):
        if selected_id is not None and case["id"] != selected_id:
            continue
        if draft["ratings"][idx]["semantic_accuracy"] is not None:
            continue
        print(f"\nID {case['id']} | {case['genre']} | {case['speaker']}")
        print("Ngữ cảnh:", case["scene_context"])
        print("Cần chú ý:", case["risk_focus"])
        print("EN:", case["source_english"])
        print("VI:", row["vi"])
        while True:
            try:
                answer = input("Điểm 5 mục + y/n (q=thoát, s=bỏ qua): ").strip()
            except (EOFError, KeyboardInterrupt):
                print("\nDỪNG. Điểm đã lưu vẫn được giữ nguyên.")
                return
            if answer.lower() in ("", "q", "quit"):
                print("TẠM DỪNG. Không tạo điểm cho câu chưa đánh giá.")
                return
            if answer.lower() in ("s", "skip"):
                break
            try:
                updated = mark_case(draft, batch, label, case["id"], answer)
            except ValueError:
                print("Sai định dạng. Cần đúng 5 số nguyên 1..5 và y hoặc n.")
                continue
            _checkpoint(out, updated)
            draft.clear()
            draft.update(updated)
            print(_status(batch, draft, label))
            break
    print(_status(batch, draft, label))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Attended local Human quality scoring; no model/API calls.")
    sub = parser.add_subparsers(dest="cmd", required=True)
    run = sub.add_parser("review", help="start/resume one 12-case scoring batch")
    run.add_argument("--translations", type=Path, required=True)
    run.add_argument("--template", type=Path, required=True)
    run.add_argument("--out", type=Path, required=True)
    run.add_argument("--case", type=int)
    run.add_argument("--confirm", required=True)
    status = sub.add_parser("status", help="show safe counts only")
    status.add_argument("--translations", type=Path, required=True)
    status.add_argument("--draft", type=Path, required=True)
    final = sub.add_parser("finish", help="write standard batch score report")
    final.add_argument("--translations", type=Path, required=True)
    final.add_argument("--draft", type=Path, required=True)
    final.add_argument("--report-out", type=Path, required=True)
    final.add_argument("--confirm", required=True)
    args = parser.parse_args()

    if args.cmd in ("review", "finish") and args.confirm != CONFIRM:
        parser.error("HUMAN_SCORE_EXPLICIT_CONFIRM_REQUIRED")
    # This check must precede printing any private dialogue or creating files.
    if args.cmd == "review" and (not sys.stdin.isatty() or not sys.stdout.isatty()):
        parser.error("HUMAN_SCORE_INTERACTIVE_TERMINAL_REQUIRED")
    translations = _load(args.translations)
    batch, label, _ = _translation_info(translations)
    if args.cmd == "review":
        template = _load(args.template)
        draft = _open_or_resume(args.out, translations, template, batch, label)
        _terminal_score(translations, draft, args.out, batch, label, args.case)
    else:
        draft = _load(args.draft)
        lock = _lock_path(args.draft)
        if args.draft.is_symlink() or lock.is_symlink() or _load(lock) != _binding(
                translations, batch, label):
            raise ValueError("HUMAN_SCORE_BINDING_MISMATCH")
        completed = _draft_status(draft, batch=batch, label=label)
        if args.cmd == "status":
            print(_status(batch, draft, label))
        else:
            if completed != 12:
                raise ValueError("HUMAN_SCORE_BATCH_INCOMPLETE_NO_REPORT")
            report = score_review(translations, draft)
            _write_new(args.report_out, _dump(report))
            print(f"BENCHMARK36_HUMAN_SCORE_RECORDED batch={batch} cases=12 quality_certified=False")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
