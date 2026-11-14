"""Automatic selected-media subtitle source -> existing P2 LEAN120, no prompts.

This is a *callable integration component* for the owner-local TV workflow.
The caller configures bounded provider/model permissions and credentials
ONCE when starting the owner-local process; selecting a media file then
performs its full VI_FAST -> selected subtitle -> EN translation in-process.
No new translator, queue, background timer, public GitHub upload or TV claims.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
from typing import Callable

from matcher import Media, _release_stem_and_accessibility, parse_release
from opensubtitles import Asset, OpenSubtitles, SubtitleApiError, write_private_cache, validate_timed_text
from owner_en_single_trial import _claim_one_post, _preflight_cache
from owner_vietsub_pipeline import (
    PipelineReceipt, _receipt, translate_existing_en,
)
from vi_en_fallback import select_vi_then_en

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
                 model_preflight: Callable[[], None] | None = None):
        if (not isinstance(client, OpenSubtitles)
                or not isinstance(cache_root, Path) or not cache_root.is_absolute()
                or not isinstance(permissions, AutoPermissions)
                or type(permissions.auto_download) is not bool
                or type(permissions.auto_translate_en) is not bool
                or not callable(getattr(worker, "run", None))
                or (model_preflight is not None
                    and not callable(model_preflight))):
            raise ValueError("AUTO_VIETSUB_INVALID_CONFIGURATION")
        self.client = client
        self.worker = worker
        self.cache_root = cache_root
        self.permissions = permissions
        self.emit = emit or (lambda _: None)
        self._model_preflight = model_preflight
        self._model_ready = False

    def _ensure_en_model_ready(self) -> None:
        # Only a source that actually needs EN->VI invokes this no-content
        # model availability check. A missing Hydrogen endpoint must not
        # prevent automatic VI downloads or terminate the Windows agent.
        # Success is cached for the lifetime of the owner process; failures
        # remain fail-closed and never trigger an alternate model.
        if self._model_ready:
            return
        if self._model_preflight is not None:
            self._model_preflight()
        self._model_ready = True
        self.emit("AUTO_GEMINI_MODEL_AVAILABLE=YES")

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
        translated = self.after_en_cached(asset, file)
        self.emit("AUTO_EN_CACHED_REUSED=YES")
        return AutoResult("VIETSUB_READY", cue_count=item["cues"],
                          translated_cues=translated.translated_cues)

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

    def selected_media(self, video_name: str, *,
                       source_fingerprint: str | None = None) -> AutoResult:
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
        parsed = parse_release(video_name)
        if not parsed.title or parsed.year is None or not parsed.group:
            return AutoResult("REVIEW_REQUIRED")
        # Validate prior to any search/download or source cache access.
        if source_fingerprint is not None and (
                not isinstance(source_fingerprint, str) or
                re.fullmatch(r"[0-9a-f]{64}", source_fingerprint) is None):
            raise ValueError("AUTO_VIETSUB_SOURCE_FINGERPRINT_INVALID")
        cached = self._reuse_source(
            video_name, source_fingerprint=source_fingerprint)
        if cached is not None:
            return cached
        # Stable local-only key used for deduplicating owner-local work.
        # NEVER treat this key as an authenticated TorrServer/OMP media key.
        media_key = source_fingerprint or hashlib.sha256(
            video_name.casefold().encode("utf-8")).hexdigest()
        media = Media("owner-auto-unverified", media_key, 0, video_name)
        route = select_vi_then_en(self.client, media, policy="VI_FAST")
        self.emit(f"AUTO_SOURCE_ROUTE={route.status}")
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
        proposed = parse_release(release)
        _, is_sdh = _release_stem_and_accessibility(release)
        if (proposed.group != parsed.group or is_sdh
                or discovery.decision.winner is None
                or any(part not in discovery.decision.winner.evidence
                       for part in ("title", "year", "source", "group", "resolution", "codec"))):
            return AutoResult("REVIEW_REQUIRED", get_requests=route.get_requests)
        # If only EN is available, check the configured model BEFORE
        # spending the OpenSubtitles download POST quota. This check sends
        # no subtitle text and runs automatically, without Human prompts.
        if route.status == "EN_TRANSLATE":
            self._ensure_en_model_ready()
        # The same private one-POST claim used by the owner trial: no duplicate
        # quota requests after an error or repeat media event.
        _preflight_cache(self.cache_root)
        _claim_one_post(self.cache_root, video_name, release)
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
            self.emit("AUTO_GEMINI_REQUESTS=0")
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
                          model_preflight: Callable[[object, str], None] | None = None
                          ) -> AutomaticVietsubFlow:
    """Owner-process bootstrap. One permission/secret load, never per-media UI.

    Host app resolves owner-local preference (enabled) once at startup and
    supplies user-owned credential environment. None of these credentials
    may be stored in GitHub, repository configs or Windows runner logs.

    The model GET is DEFERRED until an EN source needs Gemini and runs only
    once on first success per process. An unavailable Hydrogen endpoint
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
    open_key = os.environ.get("OPENSUBTITLES_API_KEY", "")
    gemini_key = os.environ.get("GEMINI_API_KEY", "")
    if (not open_key.strip() or not gemini_key.strip()
            or any(ch in open_key + gemini_key for ch in "\r\n")):
        raise ValueError("AUTO_VIETSUB_OWNER_KEYS_NOT_PROVISIONED")
    from automatic_lean120_worker import AutomaticLean120Worker
    from lean120_api import load_profile
    from owner_vietsub_pipeline import _P2, verify_gemini_developer_endpoint

    profile = load_profile(_P2 / "translator_profile.json")
    if (profile.provider, profile.model, profile.thinking_level) != (
            "gemini", "gemini-4-hydrogen", "high"):
        raise ValueError("AUTO_VIETSUB_OWNER_PROFILE_MISMATCH")

    # No model network request at owner process startup. Gemini Developer
    # API availability can differ from the documented Enterprise endpoint;
    # defer the no-subtitle GET until EN translation is truly needed.
    preflight = model_preflight or verify_gemini_developer_endpoint
    worker = AutomaticLean120Worker(
        state_root=state_root, profile=profile, glossary={},
        api_key=gemini_key,
    )
    return AutomaticVietsubFlow(
        client=OpenSubtitles(api_key=open_key),
        worker=worker, cache_root=cache_root,
        permissions=AutoPermissions(
            auto_download=True, auto_translate_en=True),
        model_preflight=lambda: preflight(profile, gemini_key),
    )
