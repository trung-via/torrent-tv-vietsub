"""P2-AISUB: recover verified, *completed* EN/VI timed subtitles without Gemini.

This is a fresh v1 recovery format, NOT the missing historical R3.1 ZIP format.
It can create a new, private cache from a matched complete EN + VI subtitle pair.
The original files, previous workdirs, and old checkpoints are NEVER changed.
Default mode is READ ONLY. There is no model, API, subprocess or network code.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import stat
from typing import Any

from cue_pipeline import apply_translations, parse_cues, render

SCHEMA = "torrent-tv-existing-vi-recovery-v1"
BATCH_SIZE = 90
MAX_INPUT_BYTES = 1_000_000
MAX_MANIFEST_BYTES = 1_000_000
MAX_BATCH_BYTES = 1_000_000
MAX_CUES = 2000
CONFIRM = "CREATE_NEW_PRIVATE_CACHE_V1"


class RecoveryError(ValueError):
    """Public errors contain fixed codes, never private source or file paths."""


def _fail(code: str) -> None:
    raise RecoveryError(code)


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _json_bytes(data: Any) -> bytes:
    return (json.dumps(data, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":")) + "\n").encode("utf-8")


def _read_private(path: Path, max_bytes: int) -> bytes:
    try:
        mode = path.lstat().st_mode
        if not stat.S_ISREG(mode):
            _fail("RECOVERY_UNSAFE_INPUT")
        size = path.stat().st_size
        if size < 1 or size > max_bytes:
            _fail("RECOVERY_INPUT_SIZE_INVALID")
        with path.open("rb") as handle:
            data = handle.read(max_bytes + 1)
        if not 0 < len(data) <= max_bytes:
            _fail("RECOVERY_INPUT_SIZE_INVALID")
        return data
    except RecoveryError:
        raise
    except (OSError, ValueError):
        _fail("RECOVERY_INPUT_NOT_READABLE")


def _parse_pair(source: bytes, translated: bytes, fmt: str):
    try:
        en = parse_cues(source, fmt)
        vi = parse_cues(translated, fmt)
    except ValueError:
        _fail("RECOVERY_INVALID_SRT_VTT")
    if len(en) != len(vi):
        _fail("RECOVERY_CUE_COUNT_MISMATCH")
    translations = {}
    unchanged = 0
    for a, b in zip(en, vi):
        if (a.number, a.start_ms, a.end_ms) != (b.number, b.start_ms, b.end_ms):
            _fail("RECOVERY_CUE_TIME_OR_ID_MISMATCH")
        if a.text == b.text:
            unchanged += 1
        translations[str(a.number)] = b.text
    if unchanged == len(en):
        _fail("RECOVERY_ALL_CUES_IDENTICAL_TO_SOURCE")
    try:
        clean = apply_translations(en, translations)
        canonical = render(clean, fmt)
    except ValueError:
        _fail("RECOVERY_UNSAFE_VI_TEXT")
    return en, vi, canonical, unchanged


def plan_existing_vi(source: bytes, translated: bytes, fmt: str) -> dict[str, Any]:
    en, _vi, canonical, unchanged = _parse_pair(source, translated, fmt)
    total = math.ceil(len(en) / BATCH_SIZE)
    return {
        "status": "EXISTING_VI_TIMING_PARITY_PASS_MEANING_UNVERIFIED",
        "format": fmt,
        "source_sha256": _sha(source),
        "existing_vi_sha256": _sha(translated),
        "canonical_vi_sha256": _sha(canonical),
        "cue_count": len(en),
        "batch_size": BATCH_SIZE,
        "batch_count": total,
        "unchanged_source_text_count": unchanged,
        "timecode_parity": "PASS",
        "semantic_review": "NOT_PERFORMED",
        "old_r31_checkpoint_compatibility": "NOT_ESTABLISHED",
        "provider_calls": 0,
        "source_or_existing_vi_modified": False,
    }


def _dest_safe_new(output_dir: Path, source_path: Path, vi_path: Path) -> None:
    try:
        parent = output_dir.parent.resolve(strict=True)
        if not parent.is_dir() or output_dir.name in ("", ".", ".."):
            _fail("RECOVERY_OUTPUT_PARENT_INVALID")
        if output_dir.exists() or output_dir.is_symlink():
            _fail("RECOVERY_OUTPUT_ALREADY_EXISTS")
        # Fresh cache must be a sibling elsewhere, not nested in legacy work/.
        if (parent.name.lower() == "work" or
            (parent / "input_manifest.json").is_file() or
            (parent / "work" / "input_manifest.json").is_file()):
            _fail("RECOVERY_OUTPUT_PARENT_IS_EXISTING_WORKDIR")
        source = source_path.resolve(strict=True)
        translated = vi_path.resolve(strict=True)
        dest = parent / output_dir.name
        if source == translated or dest == source or dest == translated:
            _fail("RECOVERY_OUTPUT_UNSAFE_ALIAS")
        if source.is_relative_to(dest) or translated.is_relative_to(dest):
            _fail("RECOVERY_OUTPUT_UNSAFE_ALIAS")
    except RecoveryError:
        raise
    except (OSError, ValueError):
        _fail("RECOVERY_OUTPUT_PARENT_INVALID")


def _write_new(path: Path, obj: dict[str, Any]) -> bytes:
    data = _json_bytes(obj)
    with path.open("xb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    return data


def create_new_v1_cache(source_path: Path, vi_path: Path, output_dir: Path, *,
                        fmt: str, confirm: str) -> dict[str, Any]:
    """Create new versioned proof cache, never import/modify old R3.1 files.

    The only permitted write target is a previously nonexistent directory.
    Unexpected failure leaves new incomplete directory for manual inspection,
    never deletes or overwrites user material.
    """
    if confirm != CONFIRM:
        _fail("RECOVERY_EXPLICIT_CONFIRMATION_REQUIRED")
    _dest_safe_new(output_dir, source_path, vi_path)
    source = _read_private(source_path, MAX_INPUT_BYTES)
    translated = _read_private(vi_path, MAX_INPUT_BYTES)
    en, vi, canonical, unchanged = _parse_pair(source, translated, fmt)
    source_sha = _sha(source)
    vi_sha = _sha(translated)
    canonical_sha = _sha(canonical)
    manifests = []
    for offset in range(0, len(en), BATCH_SIZE):
        batch_id = offset // BATCH_SIZE + 1
        segment = vi[offset:offset+BATCH_SIZE]
        cues = [{"id": c.number, "text": c.text} for c in segment]
        record = {
            "schema": SCHEMA, "source_sha256": source_sha,
            "existing_vi_sha256": vi_sha,
            "batch_id": batch_id,
            "first_cue_id": segment[0].number,
            "last_cue_id": segment[-1].number,
            "cues": cues,
        }
        raw = _json_bytes(record)
        manifests.append((batch_id, record, _sha(raw)))
    manifest = {
        "schema": SCHEMA,
        "format": fmt,
        "source_sha256": source_sha,
        "existing_vi_sha256": vi_sha,
        "canonical_vi_sha256": canonical_sha,
        "model_provenance": "UNKNOWN_IMPORTED_EXISTING_VI",
        "meaning_certified": False,
        "batch_size": BATCH_SIZE,
        "cue_count": len(en),
        "batch_count": len(manifests),
        "checkpoint_sha256": {str(n): sha for n, _, sha in manifests},
    }
    try:
        output_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
        work = output_dir / "work"
        work.mkdir(mode=0o700, parents=False, exist_ok=False)
        for num, rec, _ in manifests:
            _write_new(work / f"batch_{num:03d}.json", rec)
        _write_new(work / "input_manifest.json", manifest)
        # Never claim acceptance until all created artifacts read back/verified.
        checked = verify_new_v1_cache(source, output_dir, fmt=fmt)
        # Refuse acceptance if originals changed while building the new cache.
        if (_sha(_read_private(source_path, MAX_INPUT_BYTES)) != source_sha or
            _sha(_read_private(vi_path, MAX_INPUT_BYTES)) != vi_sha):
            _fail("RECOVERY_INPUT_CHANGED_DURING_RUN")
    except FileExistsError:
        _fail("RECOVERY_OUTPUT_ALREADY_EXISTS")
    except RecoveryError:
        raise
    except OSError:
        _fail("RECOVERY_OUTPUT_WRITE_FAILED_NEW_DIRECTORY_MAY_BE_PARTIAL")
    return {**checked, "status": "NEW_PRIVATE_CACHE_VERIFIED_NO_PROVIDER",
            "existing_vi_sha256": vi_sha, "unchanged_source_text_count": unchanged}


def verify_new_v1_cache(source: bytes, output_dir: Path, *, fmt: str) -> dict[str, Any]:
    """Strictly validate the new v1 cache only; never accept old JSON by guess."""
    try:
        en = parse_cues(source, fmt)
    except ValueError:
        _fail("RECOVERY_INVALID_SRT_VTT")
    if output_dir.is_symlink() or (output_dir / "work").is_symlink():
        _fail("RECOVERY_UNSAFE_CACHE_DIRECTORY")
    manifest_path = output_dir / "work" / "input_manifest.json"
    raw = _read_private(manifest_path, MAX_MANIFEST_BYTES)
    try:
        manifest = json.loads(raw)
    except (UnicodeError, ValueError):
        _fail("RECOVERY_MANIFEST_JSON_INVALID")
    if not isinstance(manifest, dict) or manifest.get("schema") != SCHEMA:
        _fail("RECOVERY_LEGACY_OR_UNKNOWN_SCHEMA_NO_AUTOMIGRATION")
    total = math.ceil(len(en) / BATCH_SIZE)
    sha = _sha(source)
    if (manifest.get("source_sha256") != sha or
        manifest.get("format") != fmt or
        manifest.get("batch_size") != BATCH_SIZE or
        manifest.get("cue_count") != len(en) or
        manifest.get("batch_count") != total or
        manifest.get("model_provenance") != "UNKNOWN_IMPORTED_EXISTING_VI" or
        manifest.get("meaning_certified") is not False):
        _fail("RECOVERY_MANIFEST_IDENTITY_MISMATCH")
    # Refuse stray checkpoint-shaped files; a verified cache is unambiguous.
    try:
        actual = {p.name for p in (output_dir / "work").glob("batch_*.json")}
    except OSError:
        _fail("RECOVERY_CACHE_DIR_UNREADABLE")
    if actual != {f"batch_{i:03d}.json" for i in range(1, total + 1)}:
        _fail("RECOVERY_EXTRA_OR_MISSING_CHECKPOINT")
    hashes = manifest.get("checkpoint_sha256")
    if not isinstance(hashes, dict) or set(hashes) != {str(i) for i in range(1, total+1)}:
        _fail("RECOVERY_MANIFEST_BATCH_SET_INVALID")
    vi_map: dict[str, str] = {}
    for batch_id in range(1, total + 1):
        path = output_dir / "work" / f"batch_{batch_id:03d}.json"
        raw_batch = _read_private(path, MAX_BATCH_BYTES)
        if not isinstance(hashes[str(batch_id)], str) or hashes[str(batch_id)] != _sha(raw_batch):
            _fail("RECOVERY_CHECKPOINT_HASH_MISMATCH")
        try:
            record = json.loads(raw_batch)
        except (UnicodeError, ValueError):
            _fail("RECOVERY_CHECKPOINT_JSON_INVALID")
        lo = (batch_id - 1) * BATCH_SIZE + 1
        hi = min(batch_id * BATCH_SIZE, len(en))
        if (not isinstance(record, dict) or
            set(record) != {"schema", "source_sha256", "existing_vi_sha256",
                            "batch_id", "first_cue_id", "last_cue_id", "cues"} or
            record["schema"] != SCHEMA or record["source_sha256"] != sha or
            record["existing_vi_sha256"] != manifest.get("existing_vi_sha256") or
            record["batch_id"] != batch_id or record["first_cue_id"] != lo or
            record["last_cue_id"] != hi):
            _fail("RECOVERY_CHECKPOINT_IDENTITY_MISMATCH")
        cues = record["cues"]
        if not isinstance(cues, list) or len(cues) != hi - lo + 1:
            _fail("RECOVERY_CHECKPOINT_CUE_SET_INVALID")
        for num, item in enumerate(cues, start=lo):
            if not isinstance(item, dict) or set(item) != {"id", "text"} or type(item["id"]) is not int or item["id"] != num:
                _fail("RECOVERY_CHECKPOINT_CUE_SET_INVALID")
            vi_map[str(num)] = item["text"]
    try:
        vi = apply_translations(en, vi_map)
        canonical = render(vi, fmt)
    except ValueError:
        _fail("RECOVERY_CHECKPOINT_TEXT_INVALID")
    if _sha(canonical) != manifest.get("canonical_vi_sha256"):
        _fail("RECOVERY_CANONICAL_HASH_MISMATCH")
    return {
        "status": "VERIFIED_NEW_V1_CACHE_ALL_CACHED_NO_PROVIDER",
        "source_sha256": sha,
        "canonical_vi_sha256": _sha(canonical),
        "cue_count": len(en),
        "batch_size": BATCH_SIZE,
        "batch_count": total,
        "all_cached": True,
        "legacy_r31_checkpoint_compatible": False,
        "semantic_review": "NOT_PERFORMED",
        "provider_calls": 0,
        "source_or_existing_vi_modified": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Offline existing-VI recovery, no cloud or TV effects")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--translated", type=Path)
    parser.add_argument("--new-cache-dir", type=Path)
    parser.add_argument("--verify-cache-dir", type=Path)
    parser.add_argument("--confirm", default="")
    args = parser.parse_args()
    fmt = args.source.suffix.lower().lstrip(".")
    try:
        if fmt not in ("srt", "vtt"):
            _fail("RECOVERY_SRT_OR_VTT_ONLY")
        if args.verify_cache_dir is not None:
            if args.translated is not None or args.new_cache_dir is not None:
                _fail("RECOVERY_MODE_CONFLICT")
            result = verify_new_v1_cache(_read_private(args.source, MAX_INPUT_BYTES), args.verify_cache_dir, fmt=fmt)
        else:
            if args.translated is None or args.translated.suffix.lower() != args.source.suffix.lower():
                _fail("RECOVERY_SAME_FORMAT_REQUIRED")
            if args.new_cache_dir is None:
                result = plan_existing_vi(_read_private(args.source, MAX_INPUT_BYTES),
                                          _read_private(args.translated, MAX_INPUT_BYTES),fmt)
            else:
                result = create_new_v1_cache(args.source, args.translated, args.new_cache_dir,
                                             fmt=fmt, confirm=args.confirm)
        code = 0
    except RecoveryError as exc:
        result = {"status": "BLOCKED", "error_code": str(exc), "provider_calls": 0}
        code = 2
    except (OSError, ValueError, TypeError):
        result = {"status": "BLOCKED", "error_code": "RECOVERY_INPUT_OR_CACHE_INVALID", "provider_calls": 0}
        code = 2
    print(json.dumps(result, sort_keys=True, ensure_ascii=True, separators=(",", ":")))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
