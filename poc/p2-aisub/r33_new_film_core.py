"""R3.3 new-film subtitle translation *core*, with no built-in provider transport.

The vanished R3.1 ZIP is NOT a dependency. A future separately reviewed private
Antigravity adapter supplies two callbacks, one for full-story context and one
for individual batch translation. This module never calls Gemini, shells out,
logs private subtitles, or touches TV/Windows services.

The entrypoint is intentionally inspection-only; model-driving code must call
run_new_film() explicitly with RUN_R33_NEW_FILM_V1. Each run uses a NEW, uniquely
marked workdir, locks it using a platform OS lock, and never imports a legacy
R2/R3.1 workdir. Valid checkpoints are reused with source/model/IDs validation.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import stat
from typing import Any, Callable, Iterator

from cue_pipeline import Cue, parse_cues, apply_translations, render
from r3_2_continuous_queue import QueueBlocked, QueueReport, run_continuous

SCHEMA = "torrent-tv-r33-new-film-v1"
MODEL_PIN = "ANTIGRAVITY_GEMINI_3_8_FLASH_HIGH"
RUN_CONFIRM = "RUN_R33_NEW_FILM_V1"
BATCH_SIZE = 90
MAX_FILE_BYTES = 1_000_000
MAX_BATCH_BYTES = 350_000
MAX_WORKERS = 4


class R33Blocked(RuntimeError):
    """Safe failure: fixed error code and numeric statistics only."""

    def __init__(self, code: str, *, stats: dict | None = None):
        super().__init__(code)
        self.code = code
        self.stats = stats or {}


def _fail(code: str) -> None:
    raise R33Blocked(code)


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _json(raw: Any) -> bytes:
    return (json.dumps(raw, sort_keys=True, ensure_ascii=False,
                       separators=(",", ":")) + "\n").encode("utf-8")


def _read_regular(path: Path, limit: int = MAX_BATCH_BYTES) -> bytes:
    try:
        if not stat.S_ISREG(path.lstat().st_mode) or path.is_symlink():
            _fail("R33_UNSAFE_FILE_TYPE")
        if not 0 < path.stat().st_size <= limit:
            _fail("R33_FILE_SIZE_INVALID")
        with path.open("rb") as f:
            data = f.read(limit + 1)
        if not 0 < len(data) <= limit:
            _fail("R33_FILE_SIZE_INVALID")
        return data
    except R33Blocked:
        raise
    except OSError:
        _fail("R33_FILE_UNREADABLE")


def _parse_json(path: Path, limit: int = MAX_BATCH_BYTES) -> dict:
    try:
        data = json.loads(_read_regular(path, limit))
    except R33Blocked:
        raise
    except (ValueError, UnicodeError):
        _fail("R33_JSON_INVALID")
    if type(data) is not dict:
        _fail("R33_JSON_INVALID")
    return data


def _write_new_atomic(path: Path, data: bytes) -> None:
    """Write to a private temp then hard-link at new name (never replace)."""
    if path.exists() or path.is_symlink():
        _fail("R33_EXISTING_FILE_NOT_OVERWRITTEN")
    temp = path.with_name(".r33-tmp-" + secrets.token_hex(12))
    try:
        with temp.open("xb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        # os.link atomically fails when destination exists, on Windows NTFS too.
        # An unsupported filesystem is a deliberate stop, not a silent downgrade.
        os.link(temp, path)
    except FileExistsError:
        _fail("R33_EXISTING_FILE_NOT_OVERWRITTEN")
    except OSError:
        _fail("R33_ATOMIC_NEW_FILE_UNSUPPORTED")
    finally:
        try:
            temp.unlink(missing_ok=True)
        except OSError:
            pass


def _workpath(workdir: Path) -> Path:
    if workdir.is_symlink():
        _fail("R33_UNSAFE_WORKDIR")
    root = workdir.resolve(strict=False)
    if not root.is_dir() or (root / "work").is_symlink():
        _fail("R33_WORKDIR_NOT_READY")
    return root / "work"


def _init_or_load(source: bytes, fmt: str, workdir: Path) -> tuple[tuple[Cue, ...], dict, Path]:
    if not 0 < len(source) <= MAX_FILE_BYTES or fmt not in ("srt", "vtt"):
        _fail("R33_SOURCE_SIZE_OR_FORMAT_INVALID")
    try:
        cues = parse_cues(source, fmt)
    except ValueError:
        _fail("R33_SOURCE_CUES_INVALID")
    sha = _sha(source)
    new = not workdir.exists() and not workdir.is_symlink()
    if new:
        # New path only, never inside the existing legacy work/ tree.
        try:
            parent = workdir.parent.resolve(strict=True)
            # Reject even a nested child of an old workdir, not merely one
            # direct level below it. Only known relative marker names checked.
            ancestors = (parent, *parent.parents)
            if (not parent.is_dir() or any(
                base.name.lower() == "work" or
                (base / "input_manifest.json").is_file() or
                (base / "work" / "input_manifest.json").is_file()
                for base in ancestors
            )):
                _fail("R33_PARENT_IS_LEGACY_WORKDIR")
            workdir.mkdir(mode=0o700, exist_ok=False)
            (workdir / "work").mkdir(mode=0o700, exist_ok=False)
        except R33Blocked:
            raise
        except (OSError, ValueError):
            _fail("R33_NEW_WORKDIR_CREATION_FAILED")
    work = _workpath(workdir)
    expected = {
        "schema": SCHEMA, "source_sha256": sha, "format": fmt,
        "cue_count": len(cues), "batch_size": BATCH_SIZE,
        "batch_count": math.ceil(len(cues) / BATCH_SIZE),
        "model_pin": MODEL_PIN,
        "context_policy": "FULL_STORY_CONTEXT_CALLBACK_REQUIRED_IF_UNCACHED",
    }
    manifest_file = work / "r33_manifest.json"
    if new:
        _write_new_atomic(manifest_file, _json(expected))
    actual = _parse_json(manifest_file)
    if actual != expected:
        _fail("R33_MANIFEST_SOURCE_OR_MODEL_MISMATCH")
    if work.is_symlink():
        _fail("R33_UNSAFE_WORKDIR")
    return cues, expected, work


@contextmanager
def exclusive_owner(lock_path: Path) -> Iterator[Callable[[], bool]]:
    """Fresh R3.3-only OS lock, never reused on an unknown legacy workdir."""
    if lock_path.is_symlink() or not lock_path.parent.is_dir():
        _fail("R33_OWNER_LOCK_PATH_INVALID")
    try:
        handle = lock_path.open("a+b")
    except OSError:
        _fail("R33_OWNER_LOCK_UNAVAILABLE")
    acquired = False
    active = False
    try:
        handle.seek(0, os.SEEK_END)
        if handle.tell() == 0:
            handle.write(b"\x00")
            handle.flush()
        handle.seek(0)
        if os.name == "nt":
            import msvcrt
            try:
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError:
                _fail("R33_WORKDIR_ALREADY_ACTIVE")
        else:
            import fcntl
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                _fail("R33_WORKDIR_ALREADY_ACTIVE")
        acquired, active = True, True
        yield lambda: active
    finally:
        active = False
        if acquired:
            try:
                handle.seek(0)
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
            finally:
                handle.close()
        else:
            handle.close()


def _record_for(source_sha: str, batch_id: int, segment: tuple[Cue, ...],
                translations: dict[str, str]) -> dict:
    wanted = {str(c.number) for c in segment}
    if type(translations) is not dict or set(translations) != wanted:
        _fail("R33_TRANSLATION_CUE_SET_INVALID")
    try:
        checked = apply_translations(segment, translations)
    except ValueError:
        _fail("R33_TRANSLATION_TEXT_INVALID")
    body = {
        "schema": SCHEMA, "source_sha256": source_sha, "model_pin": MODEL_PIN,
        "batch_id": batch_id,
        "first_cue": segment[0].number, "last_cue": segment[-1].number,
        "cues": [{"id": c.number, "text": c.text} for c in checked],
    }
    # A self-contained digest detects accidental valid-JSON edits/corruption.
    # It is NOT a signature or provider attestation.
    return {**body, "record_sha256": _sha(_json(body))}


def _verify_batch(path: Path, batch_id: int, source_sha: str,
                  segment: tuple[Cue, ...]) -> dict:
    rec = _parse_json(path)
    keys = {"schema", "source_sha256", "model_pin", "batch_id", "first_cue", "last_cue", "cues", "record_sha256"}
    digest = rec.get("record_sha256")
    payload = {k: v for k, v in rec.items() if k != "record_sha256"}
    if (not isinstance(digest, str) or len(digest) != 64 or
        digest != _sha(_json(payload))):
        _fail("R33_CHECKPOINT_HASH_INVALID")
    if (set(rec) != keys or rec["schema"] != SCHEMA or
        rec["source_sha256"] != source_sha or rec["model_pin"] != MODEL_PIN or
        type(rec["batch_id"]) is not int or rec["batch_id"] != batch_id or
        rec["first_cue"] != segment[0].number or rec["last_cue"] != segment[-1].number or
        type(rec["cues"]) is not list or len(rec["cues"]) != len(segment)):
        _fail("R33_CHECKPOINT_INTEGRITY_INVALID")
    mapping: dict[str, str] = {}
    for cue, item in zip(segment, rec["cues"]):
        if (type(item) is not dict or set(item) != {"id", "text"} or
            type(item["id"]) is not int or item["id"] != cue.number):
            _fail("R33_CHECKPOINT_INTEGRITY_INVALID")
        mapping[str(cue.number)] = item["text"]
    _record_for(source_sha, batch_id, segment, mapping)
    return mapping


def _stats(r: QueueReport) -> dict:
    return {"total_batches": r.total, "cached_batches": len(r.reused),
            "submitted_batches": len(r.submitted), "committed_batches": len(r.committed),
            "failed_batches": len(r.failed), "unsubmitted_batches": len(r.unsubmitted),
            "retry_count": r.retry_count}


def run_new_film(
    source: bytes, fmt: str, workdir: Path, *, confirm: str,
    full_story_context: Callable[[tuple[Cue, ...]], Any],
    translate_batch: Callable[[int, tuple[Cue, ...], Any], dict[str, str]],
    max_workers: int = 3,
) -> dict:
    """Execute a *caller-supplied* provider against a new/verified R3.3 workdir.

    No provider implementation lives in this module. Explicit confirmation is
    required and no disk files or providers are accessed on missing approval.
    """
    if confirm != RUN_CONFIRM:
        _fail("R33_RUN_CONFIRMATION_REQUIRED")
    if type(max_workers) is not int or not 1 <= max_workers <= MAX_WORKERS:
        _fail("R33_INVALID_WORKER_COUNT")
    cues, manifest, work = _init_or_load(source, fmt, workdir)
    sha = manifest["source_sha256"]
    count = manifest["batch_count"]
    batches = {i: cues[(i - 1) * BATCH_SIZE:i * BATCH_SIZE] for i in range(1, count + 1)}
    with exclusive_owner(work / ".r33_owner.lock") as owner_guard:
        checkpoint_files = {i: work / f"batch_{i:03d}.json" for i in batches}
        # In addition to verifying expected files, refuse unexpected batch files.
        actual = {p.name for p in work.glob("batch_*.json")}
        unexpected = actual - {p.name for p in checkpoint_files.values()}
        if unexpected:
            _fail("R33_UNKNOWN_BATCH_FILE_PRESENT")
        cached = [i for i, p in checkpoint_files.items() if p.exists() or p.is_symlink()]
        for i in cached:
            _verify_batch(checkpoint_files[i], i, sha, batches[i])
        missing = [i for i in batches if i not in cached]
        context: Any = None
        if missing:
            try:
                context = full_story_context(cues)
            except Exception:
                _fail("R33_FULL_STORY_CONTEXT_FAILED")
            if context is None:
                _fail("R33_FULL_STORY_CONTEXT_EMPTY")
        def provider(i: int) -> dict[str, str]:
            return translate_batch(i, batches[i], context)
        def verify(i: int, response: dict[str, str]) -> bool:
            try:
                _record_for(sha, i, batches[i], response)
                return True
            except R33Blocked:
                return False
        def commit(i: int, response: dict[str, str]) -> bool:
            try:
                rec = _record_for(sha, i, batches[i], response)
                _write_new_atomic(checkpoint_files[i], _json(rec))
                _verify_batch(checkpoint_files[i], i, sha, batches[i])
                return True
            except R33Blocked:
                return False
        try:
            report = run_continuous(
                tuple(batches), cached_ids=cached, owner_guard=owner_guard,
                verify_cached=lambda i: bool(_verify_batch(checkpoint_files[i], i, sha, batches[i])),
                invoke_provider=provider, verify_result=verify,
                commit_checkpoint=commit, max_workers=max_workers,
            )
        except QueueBlocked as e:
            raise R33Blocked("R33_" + e.code, stats=_stats(e.report) if e.report else {}) from None
        translation_map: dict[str, str] = {}
        for i in batches:
            translation_map.update(_verify_batch(checkpoint_files[i], i, sha, batches[i]))
        try:
            complete = render(apply_translations(cues, translation_map), fmt)
        except ValueError:
            _fail("R33_FINAL_RENDER_FAILED")
        if not 0 < len(complete) <= MAX_FILE_BYTES:
            _fail("R33_OUTPUT_SIZE_INVALID")
        output = workdir / ("translated.vi." + fmt)
        if output.exists() or output.is_symlink():
            if _sha(_read_regular(output, MAX_FILE_BYTES)) != _sha(complete):
                _fail("R33_EXISTING_OUTPUT_HASH_MISMATCH")
        else:
            _write_new_atomic(output, complete)
        return {"status": "R33_COMPLETE_STRUCTURE_ONLY_SEMANTICS_UNVERIFIED",
                "cue_count": len(cues), "batch_count": count, "cached_prior_batches": len(cached),
                "provider_batches": len(report.submitted), "retry_count": 0,
                "source_sha256": sha, "vi_sha256": _sha(complete),
                "model_identity_assertion": "CALLBACK_SUPPLIED_NOT_ATTESTED",
                "human_semantic_review": "REQUIRED"}


def inspect_existing(source: bytes, fmt: str, workdir: Path) -> dict:
    """Read-only source/checkpoint overview. No lock, no provider and no writes."""
    if not workdir.exists():
        return {"status": "R33_WORKDIR_NOT_CREATED", "model_calls": 0}
    try:
        cues = parse_cues(source, fmt)
        work = _workpath(workdir)
        manifest = _parse_json(work / "r33_manifest.json")
        if (manifest.get("schema") != SCHEMA or
            manifest.get("source_sha256") != _sha(source) or
            manifest.get("model_pin") != MODEL_PIN or
            manifest.get("cue_count") != len(cues)):
            _fail("R33_MANIFEST_SOURCE_OR_MODEL_MISMATCH")
        count = math.ceil(len(cues) / BATCH_SIZE)
        if manifest.get("batch_count") != count or manifest.get("batch_size") != BATCH_SIZE:
            _fail("R33_MANIFEST_SOURCE_OR_MODEL_MISMATCH")
        actual = {p.name for p in work.glob("batch_*.json")}
        expected_batch_files = {f"batch_{i:03d}.json" for i in range(1, count+1)}
        if actual - expected_batch_files:
            _fail("R33_UNKNOWN_BATCH_FILE_PRESENT")
        cached = 0
        for i in range(1, count + 1):
            p = work / f"batch_{i:03d}.json"
            if p.exists() or p.is_symlink():
                _verify_batch(p, i, manifest["source_sha256"],
                              cues[(i-1)*BATCH_SIZE:i*BATCH_SIZE])
                cached += 1
        return {"status": "R33_INSPECTION_PASS_NOT_PROVIDER_OR_SEMANTIC_ACCEPTANCE",
                "cue_count": len(cues), "batch_count": count,
                "cached_batches_valid": cached, "remaining_batches": count-cached,
                "source_sha256": _sha(source), "model_calls": 0}
    except (OSError, ValueError):
        _fail("R33_INSPECTION_FAILED")


def main() -> int:
    parser = argparse.ArgumentParser(description="R3.3 read-only source/workdir inspection only; no Gemini")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--workdir", type=Path, required=True)
    args = parser.parse_args()
    try:
        suffix = args.source.suffix.lower().lstrip(".")
        if suffix not in ("srt", "vtt"):
            _fail("R33_SRT_OR_VTT_ONLY")
        result = inspect_existing(_read_regular(args.source, MAX_FILE_BYTES), suffix, args.workdir)
        code = 0
    except R33Blocked as e:
        result, code = {"status":"BLOCKED","code":e.code,"model_calls":0}, 2
    except (OSError, ValueError, TypeError):
        result, code = {"status":"BLOCKED","code":"R33_INPUT_INVALID","model_calls":0}, 2
    print(json.dumps(result, sort_keys=True, ensure_ascii=True, separators=(",", ":")))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
