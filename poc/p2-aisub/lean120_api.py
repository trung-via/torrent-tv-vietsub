"""LEAN120 subtitle request/QA helpers and owner-local CLI entrypoint.

LEAN120 semantics: <=120 target cues / <=6500 source chars, +/-4 read-only
context cues, fixed per-film glossary, exact one-to-one IDs, original timings.

Provider choice and model ID live in an editable JSON profile, NOT in Python.
No Gemini Developer API transport is implemented or permitted. Automatic
translation runs exclusively through the replaceable local provider gateway.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
from typing import Any, Callable, Mapping

from progressive_handoff import (
    ProgressiveSubtitleSession, SubtitleRevision, TranslationWindow,
)

MODEL_ID_RX = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z")
@dataclass(frozen=True)
class ModelProfile:
    provider: str
    model: str
    thinking_level: str

    @staticmethod
    def from_json(data: Mapping[str, Any]) -> "ModelProfile":
        if not isinstance(data, dict) or set(data) != {"provider", "model", "thinking_level"}:
            raise ValueError("MODEL_PROFILE_INVALID")
        provider, model, level = (data[k] for k in ("provider", "model", "thinking_level"))
        if provider not in {"antigravity", "codex"}:
            raise ValueError("PROVIDER_ADAPTER_NOT_CONFIGURED")
        if not isinstance(model, str) or not MODEL_ID_RX.fullmatch(model):
            raise ValueError("MODEL_ID_INVALID")
        if not isinstance(level, str) or level.lower() not in {"low", "medium", "high"}:
            raise ValueError("THINKING_LEVEL_INVALID")
        return ModelProfile(provider=provider, model=model, thinking_level=level.lower())


def load_profile(path: Path) -> ModelProfile:
    return ModelProfile.from_json(json.loads(path.read_text(encoding="utf-8")))


def translate_all(
    source: bytes, fmt: str, media_key: str, profile: ModelProfile,
    *, glossary: Mapping[str, str] | None,
    runner: object | None = None,
    on_revision: Callable[[SubtitleRevision], None] | None = None,
) -> tuple[SubtitleRevision, ...]:
    """Translate sequential windows with an optional per-revision callback.

    Every callback receives a fully validated cumulative revision immediately.
    A separate publisher/TV receiver and durable checkpoint are NOT implemented.
    """
    session = ProgressiveSubtitleSession(source, fmt, media_key)
    from translator_gateway import translate_window
    revisions: list[SubtitleRevision] = []
    while (window := session.next_window()) is not None:
        if runner is None:
            translations = translate_window(window, profile, glossary=glossary or {})
        else:
            translations = translate_window(window, profile, glossary=glossary or {},
                                            runner=runner)
        revision = session.commit(
            window, translations,
            expected_version=len(revisions),
            source_sha256=session.source_sha256,
            media_key=media_key,
        )
        if on_revision is not None:
            on_revision(revision)
        revisions.append(revision)
    return tuple(revisions)


def main() -> int:
    parser = argparse.ArgumentParser(description="LEAN120 owner CLI translation (no TV controls)")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--profile", type=Path, default=Path(__file__).with_name("translator_profile.json"))
    parser.add_argument("--media-key", required=True, help="Opaque media.<64 hex> identity")
    parser.add_argument("--glossary-json", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--execute-provider", action="store_true", help="Use signed-in Antigravity CLI")
    args = parser.parse_args()
    if not args.execute_provider:
        parser.error("TRANSLATION_PROVIDER_NOT_EXECUTED_EXPLICIT_FLAG_REQUIRED")
    try:
        profile = load_profile(args.profile)
        from translator_gateway import preflight_provider
        preflight_provider(profile)
        if args.source.suffix.lower() not in (".srt", ".vtt"):
            raise ValueError("SRT_OR_VTT_REQUIRED")
        source = args.source.read_bytes()
        glossary = (json.loads(args.glossary_json.read_text(encoding="utf-8"))
                    if args.glossary_json else {})
        # Preflight the destination before any account-quota-consuming CLI call.
        args.output_dir.mkdir(parents=True, exist_ok=True)
        if any(args.output_dir.iterdir()):
            raise ValueError("OUTPUT_DIR_MUST_BE_EMPTY")
        def save_revision(revision: SubtitleRevision) -> None:
            # Emit every validated cumulative version as soon as it is ready;
            # no viewer menu selection and no overwrite of existing subtitles.
            name = f"vi-{args.media_key[6:22]}-v{revision.version:04d}.{revision.fmt}"
            with (args.output_dir / name).open("xb") as file:
                file.write(revision.payload)
                file.flush()
                os.fsync(file.fileno())

        revisions = translate_all(
            source, args.source.suffix.lower()[1:], args.media_key,
            profile, glossary=glossary,
            on_revision=save_revision,
        )
        print(f"LEAN120_PROVIDER_TRANSLATION_PASS batches={len(revisions)} "
              f"cues={revisions[-1].translated_count} "
              "tv_delivery=NOT_RUN")
        return 0
    except (ValueError, OSError, UnicodeError, TypeError) as exc:
        # Errors raised by model/provider input parsing have only safe codes.
        safe = str(exc)
        if not re.fullmatch(r"[A-Z0-9_]+", safe):
            safe = "LEAN120_PROVIDER_FAILED"
        print(safe)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
