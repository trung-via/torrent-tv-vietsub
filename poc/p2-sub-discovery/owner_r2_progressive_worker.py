"""R2 callback adapter over the already-pinned P2 checkpointed worker.

The installed F6 worker/hash is immutable. Only the new Owner composition
wraps it, with one session-scoped callback that NEVER starts an extra model
job. Delivery failure does not turn an already paid P2 checkpoint into an
uncertain job or cause a second provider call.
"""
from __future__ import annotations

from contextlib import contextmanager
from threading import local
from typing import Callable, Iterator

from automatic_lean120_worker import AutomaticLean120Worker
from assumed_source_handoff import AssumedEnglishSubtitle
from progressive_handoff import SubtitleRevision


class R2ProgressiveWorker(AutomaticLean120Worker):
    def __init__(self, *, existing: AutomaticLean120Worker,
                 emit: Callable[[str], object] = print):
        if not isinstance(existing, AutomaticLean120Worker) or not callable(emit):
            raise ValueError("OWNER_R2_EXISTING_WORKER_REQUIRED")
        super().__init__(
            state_root=existing.state_root, profile=existing.profile,
            glossary=existing.glossary, runner=existing.runner)
        self._scoped = local()
        self._emit = emit

    @contextmanager
    def bind(self, callback: Callable[[AssumedEnglishSubtitle, SubtitleRevision], None]
             ) -> Iterator[None]:
        if not callable(callback) or getattr(self._scoped, "callback", None) is not None:
            raise ValueError("OWNER_R2_CALLBACK_SCOPE_INVALID")
        self._scoped.callback = callback
        try:
            yield
        finally:
            del self._scoped.callback

    def run(self, handoff: AssumedEnglishSubtitle, *,
            on_revision: Callable[[SubtitleRevision], object] | None = None,
            max_new_windows: int | None = None) -> SubtitleRevision:
        callback = getattr(self._scoped, "callback", None)
        if callback is None:
            return super().run(
                handoff, on_revision=on_revision,
                max_new_windows=max_new_windows)

        def safely_deliver(revision: SubtitleRevision) -> None:
            # P2 committed this batch BEFORE reaching its callback. A missing
            # TV or P4 consumer may not poison that durable checkpoint and
            # must not trigger a repeat of the provider operation.
            try:
                callback(handoff, revision)
            except Exception:
                self._emit("OWNER_P4_PROGRESSIVE_HOLD_NO_PROVIDER_RETRY")
            if on_revision is not None:
                on_revision(revision)

        return super().run(
            handoff, on_revision=safely_deliver,
            max_new_windows=max_new_windows)
