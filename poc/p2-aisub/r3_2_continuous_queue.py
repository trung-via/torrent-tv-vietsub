"""P2-AISUB R3.2: fail-closed continuous batch dispatch, offline-only.

Reusable scheduler seam for the *private* R3.1 Antigravity helper. It does not
open files, acquire the OS lock, call providers, or handle real subtitle text.
The caller MUST keep its R3.1 OS Work Owner lock held for the entire trial,
verify legacy checkpoints against the exact source/manifest before passing
cached_ids, and atomically commit each valid result before returning True.

One failed call stops NEW dispatch. Already-in-flight calls drain to preserve
valid expensive results. There is no automatic retry or model fallback.
"""
from __future__ import annotations

from concurrent.futures import FIRST_COMPLETED, Future, ThreadPoolExecutor, wait
from dataclasses import dataclass
from typing import Any, Callable, Iterable, Sequence


@dataclass(frozen=True)
class QueueReport:
    total: int
    reused: tuple[int, ...]
    submitted: tuple[int, ...]
    committed: tuple[int, ...]
    failed: tuple[int, ...]
    unsubmitted: tuple[int, ...]
    stop_code: str
    retry_count: int = 0


class QueueBlocked(RuntimeError):
    """Sanitized failure, never stores/prints a provider exception or payload."""

    def __init__(self, code: str, report: QueueReport | None = None):
        super().__init__(code)
        self.code = code
        self.report = report


def _id_sequence(ids: Iterable[int], *, allow_empty: bool = False) -> tuple[int, ...]:
    data = tuple(ids)
    if (not allow_empty and not data) or any(type(i) is not int or i < 1 for i in data):
        raise QueueBlocked("R32_BAD_BATCH_IDS")
    if data != tuple(sorted(set(data))):
        raise QueueBlocked("R32_BAD_BATCH_ORDER_OR_DUPLICATE")
    return data


def run_continuous(
    expected_ids: Sequence[int],
    *,
    cached_ids: Iterable[int],
    owner_guard: Callable[[], bool],
    verify_cached: Callable[[int], bool],
    invoke_provider: Callable[[int], Any],
    verify_result: Callable[[int, Any], bool],
    commit_checkpoint: Callable[[int, Any], bool],
    max_workers: int = 3,
) -> QueueReport:
    """Fill each free worker immediately, rather than waiting for a wave.

    All supplied IDs are batch IDs, not cue IDs. Callbacks are injected by the
    *private* R3.1 caller. The owner_guard must validate its already-held OS
    lock; this scheduler does not claim to implement or replace msvcrt/fcntl.
    verify_cached must validate SHA/source, batch size and checkpoint format;
    verify_result must validate exact target cue IDs/order and text; commit
    must persist atomically and verify durable checkpoint integrity.

    An external failed provider or an invalid result stops future submissions;
    already-running calls finish and can still produce validated checkpoints.
    All error messages are status constants and numeric batch IDs only.
    """
    ids = _id_sequence(expected_ids)
    cached = _id_sequence(cached_ids, allow_empty=True)
    if type(max_workers) is not int or not 1 <= max_workers <= 4:
        raise QueueBlocked("R32_WORKERS_OUT_OF_RANGE")
    if not set(cached).issubset(ids):
        raise QueueBlocked("R32_UNKNOWN_CACHED_BATCH")
    try:
        held = owner_guard()
    except Exception:
        raise QueueBlocked("R32_OWNER_LOCK_NOT_PROVEN") from None
    if held is not True:
        raise QueueBlocked("R32_OWNER_LOCK_NOT_PROVEN")
    # No provider invocation is allowed until every reused checkpoint validates.
    for i in cached:
        try:
            valid = verify_cached(i)
        except Exception:
            raise QueueBlocked("R32_CACHED_CHECKPOINT_INVALID") from None
        if valid is not True:
            raise QueueBlocked("R32_CACHED_CHECKPOINT_INVALID")

    pending = iter(i for i in ids if i not in set(cached))
    submitted: list[int] = []
    committed: list[int] = []
    failed: list[int] = []
    halt_code = "PASS"
    futures: dict[Future[Any], int] = {}

    def submit_one(pool: ThreadPoolExecutor) -> bool:
        try:
            batch_id = next(pending)
        except StopIteration:
            return False
        futures[pool.submit(invoke_provider, batch_id)] = batch_id
        submitted.append(batch_id)
        return True

    with ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="p2-r32") as pool:
        for _ in range(max_workers):
            if not submit_one(pool):
                break
        while futures:
            finished, _ = wait(tuple(futures), return_when=FIRST_COMPLETED)
            for future in sorted(finished, key=lambda f: futures[f]):
                batch_id = futures.pop(future)
                try:
                    result = future.result()
                except Exception:
                    failed.append(batch_id)
                    if halt_code == "PASS":
                        halt_code = "R32_PROVIDER_FAILURE"
                    continue
                try:
                    good = verify_result(batch_id, result)
                except Exception:
                    good = False
                if good is not True:
                    failed.append(batch_id)
                    if halt_code == "PASS":
                        halt_code = "R32_INVALID_PROVIDER_RESULT"
                    continue
                try:
                    saved = commit_checkpoint(batch_id, result)
                except Exception:
                    saved = False
                if saved is not True:
                    failed.append(batch_id)
                    if halt_code == "PASS":
                        halt_code = "R32_CHECKPOINT_COMMIT_FAILED"
                    continue
                committed.append(batch_id)
            # Stop immediately on the first OBSERVED failure. In-flight calls
            # are not canceled/replayed; they still drain for safe checkpointing.
            if halt_code == "PASS":
                while len(futures) < max_workers and submit_one(pool):
                    pass

    attempted = set(submitted)
    report = QueueReport(
        total=len(ids), reused=cached,
        submitted=tuple(submitted), committed=tuple(sorted(committed)),
        failed=tuple(sorted(failed)),
        unsubmitted=tuple(i for i in ids if i not in set(cached) and i not in attempted),
        stop_code=halt_code,
    )
    if halt_code != "PASS":
        raise QueueBlocked(halt_code, report)
    return report
