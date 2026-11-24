"""One Owner Vietsub AI request -> staged Brain EN -> AGY P2 -> P4.

Temporary owner-selected English SRT inbox mode: do not search, call the
OpenSubtitles REST API or ask AGY to download at TV tap. Retain one existing
LEAN120 translator, cache and signed P4/G2 path, with no fallback on missing EN.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
from typing import Callable

from matcher import Media, parse_release, preferred_media_release
from local_en_direct import LocalMediaSelection, find_local_english
from opensubtitles import Asset, OpenSubtitles, SubtitleApiError, write_private_cache, validate_timed_text
from owner_torrserver_subs import (
    OwnerTorrServerSubtitleReader, SidecarInventory, TorrServerSubsUnavailable,
)
from owner_torrserver_embedded_en import (
    OwnerTorrServerEmbeddedEnglishReader, EmbeddedEnglishUnavailable,
)
from owner_en_single_trial import _claim_one_post, _preflight_cache
from owner_vietsub_pipeline import (
    PipelineReceipt, _receipt, translate_existing_en,
)
from vi_en_fallback import discover_dual_candidates, select_vi_then_en
from dual_subtitle_catalog import DualSubtitleCatalog

@dataclass(frozen=True)
class AutoPermissions:
    """Session-level owner settings, never a per-film keyboard prompt."""
    auto_download: bool = False
    auto_translate_en: bool = False


@dataclass(frozen=True)
class AutoResult:
    status: str  # VI_READY | VIETSUB_READY | REVIEW_REQUIRED
    cue_count: int = 0
    translated_cues: int = 0
    get_requests: int = 0
    download_posts: int = 0


class AutomaticVietsubFlow:
    """Integrate with selected-media event in existing owner/OMP backend.

    No subtitle text, full paths or hashes leave this component as output.
    Real media and authenticated TV binding are STILL downstream D3/P4 gates.
    This P2-only local media ID is intentionally *not* a trusted TV key.
    """

    def __init__(self, *, client: OpenSubtitles, worker: object,
                 cache_root: Path, permissions: AutoPermissions,
                 emit: Callable[[str], object] | None = None,
                 model_preflight: Callable[[], None] | None = None,
                 dual_mode: bool = False,
                 source_acquirer: Callable[[Media, Path], Asset] | None = None):
        if (not isinstance(client, OpenSubtitles)
                or not isinstance(cache_root, Path) or not cache_root.is_absolute()
                or not isinstance(permissions, AutoPermissions)
                or type(permissions.auto_download) is not bool
                or type(permissions.auto_translate_en) is not bool
                or type(dual_mode) is not bool
                or not callable(getattr(worker, "run", None))
                or (model_preflight is not None
                    and not callable(model_preflight))):
            raise ValueError("AUTO_VIETSUB_INVALID_CONFIGURATION")
        if source_acquirer is not None and not callable(source_acquirer):
            raise ValueError("AUTO_AGY_SOURCE_ACQUIRER_INVALID")
        self.client = client
        self.worker = worker
        self.cache_root = cache_root
        self.permissions = permissions
        self.emit = emit or (lambda _: None)
        self._model_preflight = model_preflight
        self._model_ready = False
        self.dual_mode = dual_mode
        self.source_acquirer = source_acquirer
        self.torrent_sidecars: OwnerTorrServerSubtitleReader | None = None
        self.torrent_embedded_en: OwnerTorrServerEmbeddedEnglishReader | None = None

    def set_torrent_sidecars(self, reader: OwnerTorrServerSubtitleReader) -> None:
        """Install one Owner-pinned localhost source, never from TV JSON."""
        if not isinstance(reader, OwnerTorrServerSubtitleReader):
            raise ValueError("AUTO_TORRENT_SIDECAR_READER_INVALID")
        self.torrent_sidecars = reader

    def set_torrent_embedded_en(self, reader: OwnerTorrServerEmbeddedEnglishReader) -> None:
        """Use only the Owner-pinned localhost profile after V3 identity checks."""
        if not isinstance(reader, OwnerTorrServerEmbeddedEnglishReader):
            raise ValueError("AUTO_TORRENT_EMBEDDED_READER_INVALID")
        self.torrent_embedded_en = reader

    def _ensure_en_model_ready(self) -> None:
        # Only a source that actually needs EN->VI invokes this no-content
        # owner-local CLI check. A missing signed-in provider must not
        # prevent automatic VI downloads or terminate the Windows agent.
        # Success is cached for the lifetime of the owner process; failures
        # remain fail-closed and never trigger an alternate model.
        if self._model_ready:
            return
        if self._model_preflight is not None:
            try:
                self._model_preflight()
            except ValueError as exc:
                # Strictly local account/CLI checks have not contacted AGY.
                # Preserve the P3 event for the bounded pre-provider retry;
                # never classify an arbitrary model error as retry-safe.
                retry_safe = {
                    "AGY_OWNER_HOME_UNAVAILABLE",
                    "AGY_CLI_NOT_INSTALLED_FOR_OWNER",
                    "AGY_ACCOUNT_SETTINGS_UNREADABLE",
                    "AGY_ACCOUNT_SETTINGS_INVALID",
                    "AGY_ACCOUNT_REQUIRED_API_KEY_MODE_REFUSED",
                    "AGY_PERSONAL_ACCOUNT_MODE_REQUIRED",
                    "AGY_APP_ACCOUNT_SETTINGS_UNREADABLE",
                    "AGY_APP_ACCOUNT_SETTINGS_INVALID",
                    "AGY_ACCOUNT_REQUIRED_ADC_MODE_REFUSED",
                }
                if (len(exc.args) == 1 and isinstance(exc.args[0], str)
                        and exc.args[0] in retry_safe):
                    from owner_session_bridge import PreProviderTransient
                    raise PreProviderTransient(
                        "AGY_OWNER_PREFLIGHT_UNAVAILABLE") from None
                raise
        self._model_ready = True
        self.emit("AUTO_TRANSLATION_PROVIDER_AVAILABLE=YES")

    def _cache_index(self, video_name: str, *,
                     source_fingerprint: str | None = None) -> Path:
        # P3's server+infohash+fileIndex distinguishes same-named files in
        # different torrents. A local unbound source keeps old behavior.
        if source_fingerprint is not None:
            if (not isinstance(source_fingerprint, str)
                    or re.fullmatch(r"[0-9a-f]{64}", source_fingerprint) is None):
                raise ValueError("AUTO_VIETSUB_SOURCE_FINGERPRINT_INVALID")
            digest = source_fingerprint
        else:
            digest = hashlib.sha256(video_name.casefold().encode("utf-8")).hexdigest()
        return self.cache_root / (".auto-source-" + digest + ".json")

    def _remember_source(self, video_name: str, path: Path, asset: Asset, *,
                         source_fingerprint: str | None = None) -> None:
        """Owner-private minimal cache receipt, never a TV media manifest."""
        if not re.fullmatch(r"[0-9a-f]{64}\.srt", path.name):
            raise SubtitleApiError("AUTO_SOURCE_CACHE_FILENAME_INVALID")
        record = {
            "schema": "TTV-LOCAL-AUTO-SOURCE-V1",
            "file": path.name,
            "language": asset.language,
            "sha256": asset.sha256,
            "cues": asset.cues,
        }
        raw = json.dumps(record, separators=(",", ":"), sort_keys=True).encode()
        location = self._cache_index(
            video_name, source_fingerprint=source_fingerprint)
        try:
            fd = os.open(location, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            if location.is_symlink() or location.read_bytes() != raw:
                raise SubtitleApiError("AUTO_SOURCE_CACHE_INDEX_CONFLICT")
            return
        with os.fdopen(fd, "wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())

    def _reuse_source(self, video_name: str, *,
                      source_fingerprint: str | None = None) -> AutoResult | None:
        """Repeat selection: bypass both OpenSubtitles and repeated Gemini calls.

        The index is only trusted if source contents recheck against SHA and
        timed-cue count. A corrupted index never triggers a provider POST.
        """
        index = self._cache_index(
            video_name, source_fingerprint=source_fingerprint)
        if not index.exists() and not index.is_symlink():
            return None
        if index.is_symlink() or not index.is_file() or index.stat().st_size > 512:
            raise SubtitleApiError("AUTO_SOURCE_CACHE_INDEX_INVALID")
        try:
            item = json.loads(index.read_text(encoding="utf-8"))
        except (UnicodeError, ValueError):
            raise SubtitleApiError("AUTO_SOURCE_CACHE_INDEX_INVALID") from None
        if not isinstance(item, dict) or set(item) != {
                "schema", "file", "language", "sha256", "cues"} or (
                    item["schema"] != "TTV-LOCAL-AUTO-SOURCE-V1") or (
                    item["language"] not in ("vi", "en")) or (
                    not isinstance(item["file"], str)
                    or not re.fullmatch(r"[0-9a-f]{64}\.srt", item["file"])) or (
                    not isinstance(item["sha256"], str)
                    or not re.fullmatch(r"[0-9a-f]{64}", item["sha256"])) or (
                    type(item["cues"]) is not int or item["cues"] < 1):
            raise SubtitleApiError("AUTO_SOURCE_CACHE_INDEX_INVALID")
        file = self.cache_root / item["file"]
        if file.is_symlink() or not file.is_file():
            raise SubtitleApiError("AUTO_SOURCE_CACHE_FILE_MISSING")
        try:
            raw = file.read_bytes()
        except OSError:
            raise SubtitleApiError("AUTO_SOURCE_CACHE_FILE_UNREADABLE") from None
        if (hashlib.sha256(raw).hexdigest() != item["sha256"]
                or validate_timed_text(raw, "srt") != item["cues"]):
            raise SubtitleApiError("AUTO_SOURCE_CACHE_DIGEST_MISMATCH")
        if item["language"] == "vi":
            self.emit("AUTO_VI_CACHED_REUSED=YES")
            return AutoResult("VI_READY", cue_count=item["cues"])
        asset = Asset(0, "en", "srt", raw, item["sha256"], item["cues"])
        # The final per-source SRT is persistent. Reopening A must neither
        # call AGY nor require the provider account to be available again.
        translated = self._reuse_finished_translation(asset, file)
        if translated is None:
            translated = self.after_en_cached(asset, file)
        self.emit("AUTO_EN_CACHED_REUSED=YES")
        return AutoResult("VIETSUB_READY", cue_count=item["cues"],
                          translated_cues=translated.translated_cues)

    def _reuse_finished_translation(self, asset: Asset,
                                    file_path: Path) -> PipelineReceipt | None:
        """Verify vi-final.srt and last LEAN120 checkpoint without a model call."""
        from automatic_lean120_worker import AutomaticLean120Worker
        from cached_en_direct_handoff import prepare_local_translation_source
        from cue_pipeline import parse_cues
        from progressive_handoff import ProgressiveSubtitleSession
        if not isinstance(self.worker, AutomaticLean120Worker):
            return None
        source = prepare_local_translation_source(
            _receipt(file_path, asset), private_root=self.cache_root)
        job = self.worker.job_fingerprint(source)
        folder = self.worker.state_root / job
        final = folder / "vi-final.srt"
        if not final.exists():
            return None
        if (folder.is_symlink() or final.is_symlink()
                or not final.is_file()):
            raise ValueError("AUTO_CACHED_VI_FINAL_INVALID")
        payload = final.read_bytes()
        if len(payload) > 256 * 1024:
            raise ValueError("AUTO_CACHED_VI_FINAL_INVALID")
        number = len(self.worker.progressive_session(source).windows)
        last = folder / f"batch-{number:04d}.json"
        try:
            row = json.loads(last.read_bytes())
            input_cues = parse_cues(source.source_bytes, source.fmt)
            output_cues = parse_cues(payload, "srt")
        except (OSError, ValueError, UnicodeError):
            raise ValueError("AUTO_CACHED_VI_FINAL_INVALID") from None
        if (last.is_symlink() or not isinstance(row, dict)
                or row.get("job") != job
                or row.get("payload_sha256") != hashlib.sha256(payload).hexdigest()
                or len(input_cues) != len(output_cues)
                or any((a.number, a.start_ms, a.end_ms, a.identifier, a.settings) !=
                       (b.number, b.start_ms, b.end_ms, b.identifier, b.settings)
                       for a, b in zip(input_cues, output_cues))):
            raise ValueError("AUTO_CACHED_VI_FINAL_INVALID")
        self.emit("AUTO_VI_FINAL_SRT_REUSED=YES")
        return PipelineReceipt(source.source_sha256, source.cue_count,
                               True, source.cue_count)

    def after_en_cached(self, asset: Asset, file_path: Path) -> PipelineReceipt:
        """Called immediately by D2 after a successful private cache write.

        If a different D2 download flow already saved EN, it hands over its
        Asset/path directly. No second provider lookup, no user approval step.
        """
        if not self.permissions.auto_translate_en:
            raise ValueError("AUTO_VIETSUB_TRANSLATION_NOT_ENABLED")
        receipt = _receipt(file_path, asset)
        # Revalidate the local receipt BEFORE a model request. For already
        # cached EN, no OpenSubtitles request is necessary or permitted.
        self._ensure_en_model_ready()
        self.emit("AUTO_EN_TO_P2=STARTED")
        result = translate_existing_en(
            receipt, cache_root=self.cache_root,
            worker=self.worker, cloud_upload_authorized=True)
        self.emit("AUTO_EN_TO_P2=COMPLETE")
        self.emit(f"AUTO_VI_CUES={result.translated_cues}")
        return result

    def _selected_media_dual(self, media: Media, fingerprint: str,
                             local: object | None) -> AutoResult:
        """Owner AI mode: cached EN, otherwise one AGY OpenSubtitles task.

        The older catalog's ai_en kind is deliberately preserved for P4 and
        already finished LEAN120 checkpoints. No automatic VI source selection.
        """
        from brain_english_inbox import (
            BrainEnglishUnavailable, acquire_brain_english,
        )
        # Temporary Brain-inbox mode always verifies a staged file first.
        # A legacy AI cache without the matching staged EN cannot win merely
        # because its film key matches. Never silently use stale subtitles.
        staged = None
        if self.source_acquirer is acquire_brain_english:
            try:
                staged = acquire_brain_english(media, self.cache_root)
            except BrainEnglishUnavailable as exc:
                if str(exc) == "BRAIN_EN_NOT_STAGED":
                    self.emit("AUTO_EN_SOURCE=BRAIN_EN_NOT_STAGED")
                    return AutoResult("REVIEW_REQUIRED")
                raise
        catalog = DualSubtitleCatalog(self.cache_root)
        ai = catalog.read(media, fingerprint, "ai_en")
        if ai is None and staged is None:
            imported = catalog.import_legacy(media, fingerprint, only_en=True)
            if imported is not None and imported.kind == "ai_en":
                ai = imported
        if ai is not None and staged is not None and ai.sha256 != staged.sha256:
            self.emit("AUTO_EN_SOURCE=BRAIN_EN_CACHE_CONFLICT")
            return AutoResult("REVIEW_REQUIRED")
        if ai is not None:
            data = ai.file.read_bytes()
            source = Asset(0, "en", "srt", data, ai.sha256, ai.cues)
            translated = self._reuse_finished_translation(source, ai.file)
            if translated is None:
                translated = self.after_en_cached(source, ai.file)
            self.emit("AUTO_DUAL_AI_CACHED_REUSED=YES")
            return AutoResult("VIETSUB_READY", cue_count=ai.cues,
                              translated_cues=translated.translated_cues)
        if self.source_acquirer is not None:
            # Production path: AGY owns the discovery method and EN download.
            # The Owner only verifies the matching SRT, caches it, invokes the
            # existing AGY LEAN120 translator, then hands VI to existing P4.
            # Do not branch through local MKV/sidecars, VI lookup or a second
            # OpenSubtitles client here, even if they happen to exist.
            from agy_opensubtitles_acquisition import AgyEnglishUnavailable
            from brain_english_inbox import BrainEnglishUnavailable
            try:
                en_asset = staged if staged is not None else self.source_acquirer(
                    media, self.cache_root)
            except BrainEnglishUnavailable as exc:
                if str(exc) == "BRAIN_EN_NOT_STAGED":
                    self.emit("AUTO_EN_SOURCE=BRAIN_EN_NOT_STAGED")
                    return AutoResult("REVIEW_REQUIRED")
                raise
            except AgyEnglishUnavailable as exc:
                if str(exc) == "AGY_EN_NO_MATCH":
                    self.emit("AUTO_EN_SOURCE=AGY_OPENSUB_NO_MATCH")
                    return AutoResult("REVIEW_REQUIRED")
                raise
            if (not isinstance(en_asset, Asset) or en_asset.language != "en"
                    or en_asset.fmt != "srt"):
                raise ValueError("AUTO_AGY_EN_SOURCE_INVALID")
            self._ensure_en_model_ready()
            en_file = write_private_cache(self.cache_root, media, en_asset)
            catalog.record(media, fingerprint, "ai_en", en_asset, en_file,
                           release_matched=True)
            if not self._cache_index(
                    media.filename, source_fingerprint=fingerprint).exists():
                self._remember_source(media.filename, en_file, en_asset,
                                      source_fingerprint=fingerprint)
            translated = self.after_en_cached(en_asset, en_file)
            if not translated.translation_complete:
                raise ValueError("AUTO_AGY_EN_INCOMPLETE_TRANSLATION")
            self.emit("AUTO_EN_SOURCE=VERIFIED_EN_STAGED_OR_ACQUIRED")
            return AutoResult("VIETSUB_READY", cue_count=en_asset.cues,
                              translated_cues=translated.translated_cues)
        en_asset: Asset | None = None
        source_label: str | None = None
        if local is not None:
            en_asset = local.asset
            source_label = "LOCAL_DIRECT"
        if en_asset is None and self.torrent_embedded_en is not None:
            try:
                en_asset = self.torrent_embedded_en.extract(
                    media, private_root=self.cache_root)
                source_label = "TORRENT_EMBEDDED"
            except EmbeddedEnglishUnavailable as exc:
                self.emit("AUTO_EN_EMBEDDED=" + str(exc))
        if en_asset is None and self.torrent_sidecars is not None:
            try:
                inventory = self.torrent_sidecars.list_for_media(media)
                if inventory.en is not None:
                    en_asset = self.torrent_sidecars.download(inventory, inventory.en)
                    source_label = "TORRENT_SIDECAR"
            except TorrServerSubsUnavailable:
                self.emit("AUTO_TORRENT_EN=UNAVAILABLE")
        if en_asset is None:
            self.emit("AUTO_EN_SOURCE=UNAVAILABLE_NO_PROVIDER_FALLBACK")
            return AutoResult("REVIEW_REQUIRED")
        en_file = (local.private_cache_file if local is not None
                   else write_private_cache(self.cache_root, media, en_asset))
        catalog.record(media, fingerprint, "ai_en", en_asset, en_file,
                       release_matched=(source_label != "LOCAL_DIRECT"))
        if not self._cache_index(
                media.filename, source_fingerprint=fingerprint).exists():
            self._remember_source(media.filename, en_file, en_asset,
                                  source_fingerprint=fingerprint)
        translated = self.after_en_cached(en_asset, en_file)
        if not translated.translation_complete:
            raise ValueError("AUTO_TORRENT_EN_INCOMPLETE_TRANSLATION")
        self.emit("AUTO_EN_SOURCE=" + source_label)
        return AutoResult("VIETSUB_READY", cue_count=en_asset.cues,
                          translated_cues=translated.translated_cues)

    def selected_media(self, video_name: str, *,
                       source_fingerprint: str | None = None,
                       verified_media: Media | None = None,
                       local_source: LocalMediaSelection | None = None) -> AutoResult:
        """A single owner-local call from an existing TV/media selection event.

        Search exactly once, download the unique highest-confidence source
        once, auto-trigger P2 after EN cache write. No manual per-film prompts.
        """
        if not (self.permissions.auto_download and self.permissions.auto_translate_en):
            raise ValueError("AUTO_VIETSUB_PERMISSIONS_NOT_ENABLED")
        if (not isinstance(video_name, str) or not video_name.strip()
                or len(video_name) > 255 or "/" in video_name or "\\" in video_name
                or any(ord(c) < 32 for c in video_name)):
            raise ValueError("AUTO_VIETSUB_INVALID_MEDIA_NAME")
        # Validate prior to any search/download or source cache access.
        if source_fingerprint is not None and (
                not isinstance(source_fingerprint, str) or
                re.fullmatch(r"[0-9a-f]{64}", source_fingerprint) is None):
            raise ValueError("AUTO_VIETSUB_SOURCE_FINGERPRINT_INVALID")
        # V3 path: source identity is derived from CURRENT TV and exact
        # TorrServer selected-file metadata by VerifiedV3Processor, not an
        # arbitrary browser filename or an owner-inbox boolean.
        if verified_media is not None:
            if (not isinstance(verified_media, Media)
                    or verified_media.filename != video_name
                    or source_fingerprint is None):
                raise ValueError("AUTO_V3_VERIFIED_MEDIA_REQUIRED")
            expected_fp = hashlib.sha256(("\x00".join((
                verified_media.server_profile_id,
                verified_media.torrent_hash.lower(),
                str(verified_media.file_index)))).encode("utf-8")).hexdigest()
            if expected_fp != source_fingerprint:
                raise ValueError("AUTO_V3_SOURCE_FINGERPRINT_MISMATCH")
        elif local_source is not None:
            raise ValueError("AUTO_V3_LOCAL_SOURCE_REQUIRES_MEDIA")

        local = None
        if (local_source is not None
                and not (self.dual_mode and self.source_acquirer is not None)):
            if (not isinstance(local_source, LocalMediaSelection)
                    or local_source.video_name != video_name
                    or (local_source.server_id,
                        local_source.torrent_hash.lower(),
                        local_source.file_index) != (
                        verified_media.server_profile_id,
                        verified_media.torrent_hash.lower(),
                        verified_media.file_index)):
                raise ValueError("AUTO_V3_LOCAL_SOURCE_IDENTITY_MISMATCH")
            # Identity and local source QA run BEFORE cache reuse. Otherwise
            # stale/tampered local inputs could be masked by a prior index.
            local = find_local_english(
                local_source, cache_root=self.cache_root)

        if self.dual_mode:
            if verified_media is None or source_fingerprint is None:
                raise ValueError("AUTO_DUAL_VERIFIED_MEDIA_REQUIRED")
            return self._selected_media_dual(
                verified_media, source_fingerprint, local)

        cached = self._reuse_source(
            video_name, source_fingerprint=source_fingerprint)
        if cached is not None:
            return cached
        if local is not None:
            # No OpenSubtitles GET/POST for a valid local EN. Preserve the
            # same private per-source receipt and existing P2 checkpoint.
            self._ensure_en_model_ready()
            self._remember_source(
                video_name, local.private_cache_file, local.asset,
                source_fingerprint=source_fingerprint)
            translated = self.after_en_cached(
                local.asset, local.private_cache_file)
            if not translated.translation_complete:
                raise ValueError("AUTO_LOCAL_EN_INCOMPLETE_TRANSLATION")
            self.emit("AUTO_EN_SOURCE=LOCAL_DIRECT")
            return AutoResult(
                "VIETSUB_READY", cue_count=local.asset.cues,
                translated_cues=translated.translated_cues)

        # Stable local-only key used for deduplicating owner-local work.
        # NEVER treat this key as an authenticated TorrServer/OMP media key.
        media_key = source_fingerprint or hashlib.sha256(
            video_name.casefold().encode("utf-8")).hexdigest()
        media = verified_media or Media("owner-auto-unverified", media_key, 0, video_name)
        inventory: SidecarInventory | None = None
        if verified_media is not None and self.torrent_sidecars is not None:
            try:
                inventory = self.torrent_sidecars.list_for_media(verified_media)
            except TorrServerSubsUnavailable:
                self.emit("AUTO_TORRENT_SIDECARS=UNAVAILABLE_FALLBACK")
            if inventory is not None and inventory.vi is not None:
                try:
                    vi_asset = self.torrent_sidecars.download(inventory, inventory.vi)
                except TorrServerSubsUnavailable:
                    self.emit("AUTO_TORRENT_VI=UNAVAILABLE_FALLBACK")
                else:
                    vi_path = write_private_cache(self.cache_root, media, vi_asset)
                    self._remember_source(
                        video_name, vi_path, vi_asset,
                        source_fingerprint=source_fingerprint)
                    self.emit("AUTO_VI_SOURCE=TORRENT_SIDECAR")
                    self.emit("AUTO_AI_TRANSLATION_REQUESTS=0")
                    return AutoResult("VI_READY", cue_count=vi_asset.cues)

        # A signed TorrentServer file and its cached /subs companions do not
        # depend on scene-release metadata. Parse the filename ONLY if we
        # actually need an external title search. In particular, ordinary
        # torrent filenames without a year, group or codec are valid inputs.
        if not preferred_media_release(media).title:
            if inventory is None or inventory.en is None:
                self.emit("AUTO_PROVIDER_SEARCH=NO_TITLE")
                return AutoResult("REVIEW_REQUIRED")
            # An exact-torrent English companion remains usable even when a
            # title search is impossible. No provider GET/POST is made.
            try:
                en_asset = self.torrent_sidecars.download(inventory, inventory.en)
            except TorrServerSubsUnavailable:
                self.emit("AUTO_TORRENT_EN=UNAVAILABLE_FALLBACK")
                return AutoResult("REVIEW_REQUIRED")
            en_path = write_private_cache(self.cache_root, media, en_asset)
            self._remember_source(
                video_name, en_path, en_asset,
                source_fingerprint=source_fingerprint)
            translated = self.after_en_cached(en_asset, en_path)
            if not translated.translation_complete:
                raise ValueError("AUTO_TORRENT_EN_INCOMPLETE_TRANSLATION")
            self.emit("AUTO_EN_SOURCE=TORRENT_SIDECAR")
            return AutoResult("VIETSUB_READY", cue_count=en_asset.cues,
                              translated_cues=translated.translated_cues)

        # Privacy-safe runtime proof that the Owner used the bilingual
        # torrent label, rather than the non-Latin MKV basename, for D2.
        title_origin = ("TORRENT_ALIAS" if preferred_media_release(media).title
                        != parse_release(video_name).title else "VIDEO_FILENAME")
        self.emit("AUTO_PROVIDER_TITLE_SOURCE=" + title_origin)
        route = select_vi_then_en(
            self.client, media, policy="VI_FAST",
            external_en_available=(inventory is not None and inventory.en is not None))
        if route.status == "EXTERNAL_EN":
            try:
                en_asset = self.torrent_sidecars.download(inventory, inventory.en)
            except TorrServerSubsUnavailable:
                self.emit("AUTO_TORRENT_EN=UNAVAILABLE_FALLBACK")
                # VI was already checked; do not pay for another VI GET.
                route = select_vi_then_en(self.client, media, policy="EN_DIRECT")
            else:
                en_path = write_private_cache(self.cache_root, media, en_asset)
                self._remember_source(
                    video_name, en_path, en_asset,
                    source_fingerprint=source_fingerprint)
                translated = self.after_en_cached(en_asset, en_path)
                if not translated.translation_complete:
                    raise ValueError("AUTO_TORRENT_EN_INCOMPLETE_TRANSLATION")
                self.emit("AUTO_EN_SOURCE=TORRENT_SIDECAR")
                return AutoResult(
                    "VIETSUB_READY", cue_count=en_asset.cues,
                    translated_cues=translated.translated_cues,
                    get_requests=route.get_requests)
        # Owner-private, bounded evidence for the *real* provider response.
        # Do not emit raw releases, file IDs, torrent IDs, URLs or text. This
        # is populated during normal P2 discovery using the existing GETs;
        # no diagnostic replay of the billable/credentialed job is needed.
        self.emit(f"AUTO_SOURCE_ROUTE={route.status}")
        self.emit(f"AUTO_SOURCE_ROUTE_REASON={route.reason}")
        self.emit(f"AUTO_PROVIDER_GET_REQUESTS={route.get_requests}")
        for tag, discovery in (("VI", route.vi), ("EN", route.en)):
            if discovery is None or (tag == "VI" and route.vi_probe_status == "SKIPPED"):
                self.emit(f"AUTO_{tag}_SEARCHED=NO")
                continue
            self.emit(f"AUTO_{tag}_SEARCHED=YES")
            self.emit(f"AUTO_{tag}_RAW_ROWS={discovery.raw_rows}")
            self.emit(f"AUTO_{tag}_API_TOTAL={discovery.api_total if discovery.api_total is not None else 'UNKNOWN'}")
            self.emit(f"AUTO_{tag}_RANKED={len(discovery.decision.ranked)}")
            self.emit(f"AUTO_{tag}_CONFIDENT={sum(r.confident for r in discovery.decision.ranked)}")
            if discovery.decision.ranked:
                leader = discovery.decision.ranked[0]
                self.emit(f"AUTO_{tag}_TOP_SCORE={leader.score}")
                self.emit(f"AUTO_{tag}_TOP_CONFIDENT={'YES' if leader.confident else 'NO'}")
                name = next((c.subtitle.release_name for c in discovery.candidates
                             if c.subtitle.subtitle_id == leader.subtitle_id), None)
                if name is not None:
                    target = preferred_media_release(media)
                    candidate = parse_release(name)
                    for field in ("year", "source", "group", "resolution", "codec"):
                        expected = getattr(target, field)
                        actual = getattr(candidate, field)
                        relation = ("MISSING" if expected is None or actual is None
                                    else "MATCH" if expected == actual else "CONFLICT")
                        self.emit(f"AUTO_{tag}_TOP_{field.upper()}={relation}")
        if route.status not in ("VI_READY", "EN_TRANSLATE"):
            return AutoResult("REVIEW_REQUIRED", get_requests=route.get_requests)
        discovery = route.vi if route.status == "VI_READY" else route.en
        if discovery is None or route.selected_file_id is None:
            return AutoResult("REVIEW_REQUIRED", get_requests=route.get_requests)
        matches = [c for c in discovery.candidates
                   if c.file_id == route.selected_file_id
                   and c.subtitle.language == route.language]
        if len(matches) != 1:
            return AutoResult("REVIEW_REQUIRED", get_requests=route.get_requests)
        release = matches[0].subtitle.release_name
        # D1 already required a unique, sufficiently matched candidate. A
        # second six-field scene-name gate used to discard its own winner
        # (and even SDH-only tracks), leaving P4 with EN_INDEX_NOT_READY.
        # Never add a paid-provider POST if the chosen winner changed.
        if (discovery.decision.winner is None
                or discovery.decision.winner.subtitle_id != str(route.selected_file_id)
                or not discovery.decision.winner.confident):
            return AutoResult("REVIEW_REQUIRED", get_requests=route.get_requests)
        # If only EN is available, check the configured model BEFORE
        # spending the OpenSubtitles download POST quota. This check sends
        # no subtitle text and runs automatically, without Human prompts.
        if route.status == "EN_TRANSLATE":
            self._ensure_en_model_ready()
        # The same private one-POST claim used by the owner trial: no duplicate
        # quota requests after an error or repeat media event.
        _preflight_cache(self.cache_root)
        # The paid download claim belongs to the exact V3 server/torrent/file
        # when verified; the legacy filename-only claim remains unchanged.
        # Legacy V1/V2 remains filename-scoped and conservative. Only
        # separately verified V3 media may split the outer claim by actual
        # server/hash/index. The existing provider manual-once claim still
        # prevents ambiguous second downloads of the same release.
        _claim_one_post(
            self.cache_root,
            source_fingerprint if verified_media is not None else video_name,
            release)
        self.emit("AUTO_PROVIDER_DOWNLOAD=ATTEMPTED_ONCE")
        if route.status == "EN_TRANSLATE":
            asset = self.client.download_manual_en(
                media, discovery, file_id=route.selected_file_id, authorized=True)
        else:
            asset = self.client.download_selected(media, discovery)
        file_path = write_private_cache(self.cache_root, media, asset)
        self._remember_source(
            video_name, file_path, asset,
            source_fingerprint=source_fingerprint)
        self.emit("AUTO_SUBTITLE_CACHED=YES")
        if asset.language == "vi":
            self.emit("AUTO_AI_TRANSLATION_REQUESTS=0")
            return AutoResult("VI_READY", cue_count=asset.cues,
                              get_requests=route.get_requests, download_posts=1)
        if asset.language != "en":
            raise SubtitleApiError("AUTO_VIETSUB_BAD_SOURCE_LANGUAGE")
        translated = self.after_en_cached(asset, file_path)
        if not translated.translation_complete:
            raise ValueError("AUTO_VIETSUB_INCOMPLETE_TRANSLATION")
        return AutoResult("VIETSUB_READY", cue_count=asset.cues,
                          translated_cues=translated.translated_cues,
                          get_requests=route.get_requests, download_posts=1)



def build_owner_auto_flow(*, enabled: bool, cache_root: Path, state_root: Path,
                          model_preflight: Callable[[], None] | None = None
                          ) -> AutomaticVietsubFlow:
    """Owner bootstrap: one Brain-staged English SRT, then AGY translation.

    Host app resolves owner-local preference (enabled) once at startup and
    supplies user-owned credential environment. None of these credentials
    may be stored in GitHub, repository configs or Windows runner logs.

    The CLI preflight is DEFERRED until an EN source needs translation and
    runs only once on first success per process. An unavailable account CLI
    must never prevent VI-only work or kill the owner agent at startup.
    The authenticated OMP event consumer calls selected_media(video_name).
    """
    if enabled is not True:
        raise ValueError("AUTO_VIETSUB_OWNER_SETTING_DISABLED")
    if (os.environ.get("CI", "").lower() == "true"
            or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"):
        raise ValueError("AUTO_VIETSUB_LIVE_PROVIDER_FORBIDDEN_IN_CI")
    if (not isinstance(cache_root, Path) or not cache_root.is_absolute()
            or not isinstance(state_root, Path) or not state_root.is_absolute()
            or cache_root.is_symlink() or state_root.is_symlink()):
        raise ValueError("AUTO_VIETSUB_PRIVATE_ROOT_REQUIRED")
    from automatic_lean120_worker import AutomaticLean120Worker
    from lean120_api import load_profile
    from owner_vietsub_pipeline import _P2
    from translator_gateway import preflight_provider, provider_enabled
    from brain_english_inbox import acquire_brain_english

    profile = load_profile(_P2 / "translator_profile.json")
    if not provider_enabled(profile.provider):
        raise ValueError("AUTO_VIETSUB_PROVIDER_NOT_ENABLED")

    # No CLI/model/web request at startup or while an EN file is missing.
    # A signed TV tap binds the exact staged SRT to the existing AGY translator.
    preflight = model_preflight or (lambda: preflight_provider(profile))
    # Candidate opt-in only; installed Owner defaults stay sequential until
    # the multi-inflight diagnostic and live throughput gates are accepted.
    # Changing concurrency does not change the existing job fingerprint.
    parallel = os.environ.get("TTV_LEAN120_PARALLEL_BATCHES", "1")
    if parallel not in ("1", "2", "3"):
        raise ValueError("AUTO_LEAN120_PARALLEL_LIMIT_INVALID")
    worker = AutomaticLean120Worker(
        state_root=state_root, profile=profile, glossary={},
        first_window_cues=50, parallel_batches=int(parallel),
        preserve_hydrogen_jobs=True,
    )

    def provider_disabled(*_args: object) -> bytes:
        # Keep the old client shape for source compatibility only. The agent
        # chooses its permitted OpenSubtitles method; this client stays inert.
        raise SubtitleApiError("AUTO_PROVIDER_SEARCH_DISABLED")

    return AutomaticVietsubFlow(
        # The active verified Owner path never calls this compatibility
        # client; an OpenSubtitles credential is no longer required.
        client=OpenSubtitles(api_key="owner-torrent-only",
                             transport=provider_disabled),
        worker=worker, cache_root=cache_root,
        permissions=AutoPermissions(
            auto_download=True, auto_translate_en=True),
        model_preflight=lambda: preflight(),
        dual_mode=True,
        source_acquirer=acquire_brain_english,
    )
