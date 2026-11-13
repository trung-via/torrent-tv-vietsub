"""Single owner-local D2 EN cache -> existing P2 LEAN120 controller.

No new translator, manifest, queue, daemon, OpenSubtitles retry or P4/TV path.
Only intended for owner-authorized subtitle text: it never starts a cloud call
without an explicit upstream grant and a configured worker. No network on import.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import sys
from typing import Callable

# The existing repo PoCs are separate local sibling directories, not Python
# packages. Resolve our fixed sibling from source location; never use a user
# supplied PYTHONPATH or dynamic import target.
_P2 = (Path(__file__).resolve().parent.parent / "p2-aisub").resolve()
if str(_P2) not in sys.path:
    sys.path.insert(0, str(_P2))

from cached_en_direct_handoff import (
    CachedEnReceipt,
    prepare_local_translation_source,
    run_local_translation,
)
from opensubtitles import Asset, OpenSubtitles
from owner_en_single_trial import download_one_exact_en


@dataclass(frozen=True)
class PipelineReceipt:
    """No source text or TV identity is stored in this return value."""
    source_sha256: str
    cue_count: int
    translation_complete: bool
    translated_cues: int


def _receipt(path: Path, asset: Asset) -> CachedEnReceipt:
    if not isinstance(asset, Asset) or asset.language != "en" or asset.fmt != "srt":
        raise ValueError("OWNER_PIPELINE_EN_ASSET_REQUIRED")
    return CachedEnReceipt(path, asset.sha256, asset.cues, language=asset.language)


def validate_existing_en(receipt: CachedEnReceipt, *, cache_root: Path
                         ) -> PipelineReceipt:
    """Read existing cache and confirm receipt, with NO provider/TV call."""
    validated = prepare_local_translation_source(receipt, private_root=cache_root)
    return PipelineReceipt(validated.source_sha256, validated.cue_count,
                           False, 0)


def translate_existing_en(receipt: CachedEnReceipt, *, cache_root: Path,
                          worker: object,
                          cloud_upload_authorized: bool = False) -> PipelineReceipt:
    """No repeat OpenSubtitles GET/POST; existing P2 worker handles all batches."""
    final = run_local_translation(
        receipt, private_root=cache_root, worker=worker,
        cloud_upload_authorized=cloud_upload_authorized,
    )
    if not final.complete or final.translated_count != receipt.cue_count:
        raise ValueError("OWNER_PIPELINE_LEAN120_INCOMPLETE")
    return PipelineReceipt(receipt.source_sha256, receipt.cue_count,
                           True, final.translated_count)


def acquire_and_translate_en_once(
    client: OpenSubtitles, *, video_name: str,
    exact_en_release: str, group: str, cache_root: Path,
    worker: object, cloud_upload_authorized: bool = False,
    ask: Callable[[str], str] = input,
    emit: Callable[[str], object] = print,
) -> PipelineReceipt | None:
    """D2 one search/download/cache → in-process P2, without extra handoffs.

    This is for a *new* approved EN acquisition only. A previously-downloaded
    EN source must use translate_existing_en() and never POST again.
    Download consent is the D2 'DOWNLOAD ONE' prompt; cloud-upload consent
    is a separate prior explicit grant. Reject the missing cloud grant BEFORE
    any quota-bearing search or download.
    """
    if cloud_upload_authorized is not True:
        raise ValueError("OWNER_PIPELINE_CLOUD_UPLOAD_CONSENT_REQUIRED")
    if not callable(getattr(worker, "run", None)):
        raise ValueError("OWNER_PIPELINE_P2_WORKER_REQUIRED")

    translated: list[PipelineReceipt] = []

    def _after_d2_cache(path: Path, asset: Asset) -> None:
        receipt = _receipt(path, asset)
        emit("P2_DIRECT_CACHE_HANDOFF=STARTED")
        try:
            result = translate_existing_en(
                receipt, cache_root=cache_root, worker=worker,
                cloud_upload_authorized=True,
            )
        except Exception:
            # Preserve original private exception for owner-side diagnosis.
            # Never print subtitle/provider text in the pipeline's statuses.
            emit("P2_DIRECT_CACHE_HANDOFF=STOP_PRIVATE_REVIEW")
            raise
        translated.append(result)
        emit("P2_DIRECT_CACHE_HANDOFF=COMPLETE")
        emit(f"P2_TRANSLATED_CUES={result.translated_cues}")
        emit("P4_TV_DELIVERY=NOT_RUN")

    code = download_one_exact_en(
        client, video_name, exact_en_release, group,
        cache_root=cache_root, ask=ask, emit=emit,
        on_cached_en=_after_d2_cache,
    )
    if code != 0:
        raise ValueError("OWNER_PIPELINE_D2_FAILED")
    return translated[0] if translated else None


_SHA_64 = re.compile(r"[0-9a-f]{64}\Z")
_CACHE_BASENAME = re.compile(r"[0-9a-f]{64}\.srt\Z")


def main(argv: list[str] | None = None) -> int:
    """Local cached EN entrypoint, never queries OpenSubtitles or starts TV.

    Default = READ-ONLY verification. --execute-api needs a second explicit
    --authorize-cloud-upload and local GEMINI_API_KEY. Real provider use must
    be separately authorized by Human, not inferred from a download receipt.
    """
    parser = argparse.ArgumentParser(description="Verify existing EN cache; opt-in P2 Gemini")
    parser.add_argument("--cache-filename", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--cues", type=int, required=True)
    parser.add_argument("--execute-api", action="store_true")
    parser.add_argument("--authorize-cloud-upload", action="store_true")
    args = parser.parse_args(argv)

    # Reject even malformed approval flags before reading a private subtitle.
    if (not _CACHE_BASENAME.fullmatch(args.cache_filename)
            or not _SHA_64.fullmatch(args.sha256)
            or type(args.cues) is not int or args.cues < 1):
        print("P2_CACHE_RECEIPT_ARGS_INVALID")
        return 1
    if args.authorize_cloud_upload and not args.execute_api:
        print("P2_CLOUD_GRANT_WITHOUT_EXECUTION_INVALID")
        return 1
    if args.execute_api and not args.authorize_cloud_upload:
        print("P2_CLOUD_UPLOAD_AUTHORIZATION_REQUIRED")
        return 1
    if args.execute_api and (os.environ.get("CI", "").lower() == "true"
                             or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"):
        print("P2_LIVE_PROVIDER_FORBIDDEN_IN_CI")
        return 1

    local = os.environ.get("LOCALAPPDATA")
    if not local:
        print("P2_OWNER_LOCALAPPDATA_REQUIRED")
        return 1
    private_root = Path(local) / "TorrentTVVietsub" / "subtitle-trials"
    receipt = CachedEnReceipt(private_root / args.cache_filename,
                              args.sha256, args.cues)
    try:
        ready = validate_existing_en(receipt, cache_root=private_root)
        print("P2_CACHED_EN_REVALIDATED=PASS")
        print(f"P2_CACHED_EN_CUES={ready.cue_count}")
        print("OPEN_SUBTITLES_GET_POST=0")
        print("D3_MANIFEST=NOT_CREATED")
        print("TV_DELIVERY=NOT_RUN")
        if not args.execute_api:
            print("GEMINI_API_REQUESTS=0")
            print("NEXT_GATE=EXPLICIT_CLOUD_UPLOAD_AUTHORIZATION")
            return 0

        key = os.environ.get("GEMINI_API_KEY", "")
        if not key.strip() or "\n" in key or "\r" in key:
            print("P2_GEMINI_API_KEY_REQUIRED")
            return 1
        from automatic_lean120_worker import AutomaticLean120Worker
        from lean120_api import load_profile
        profile = load_profile(_P2 / "translator_profile.json")
        worker = AutomaticLean120Worker(
            state_root=Path(local) / "TorrentTVVietsub" / "P2" / "auto-lean120-state",
            profile=profile, glossary={}, api_key=key)
        result = translate_existing_en(
            receipt, cache_root=private_root, worker=worker,
            cloud_upload_authorized=True)
        print("P2_LOCAL_LEAN120=COMPLETE")
        print(f"P2_LOCAL_TRANSLATED_CUES={result.translated_cues}")
        print("TV_DELIVERY=NOT_RUN")
        return 0
    except (ValueError, OSError):
        # Never print raw errors: cloud adapters and local paths may contain
        # private data. Check the owner-private checkpoint state before retry.
        print("P2_LOCAL_TRANSLATION_STOP_PRIVATE_REVIEW")
        print("NO_AUTOMATIC_PROVIDER_RETRY=YES")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
