"""Single owner-local D2 EN cache -> existing P2 LEAN120 controller.

No new translator, manifest, queue, daemon, OpenSubtitles retry or P4/TV path.
Only intended for owner-authorized subtitle text: it never starts a cloud call
without an explicit upstream grant and a configured worker. No network on import.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
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
        result = translate_existing_en(
            receipt, cache_root=cache_root, worker=worker,
            cloud_upload_authorized=True,
        )
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
