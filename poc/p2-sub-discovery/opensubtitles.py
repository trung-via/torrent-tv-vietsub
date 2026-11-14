"""D2 OpenSubtitles REST acquisition for owner-authorized media.

Free-first; all network and local-cache side effects require an explicit caller.
No TorrServer, TV, model, login or background worker integration in this module.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request
from typing import Callable

from matcher import Decision, Media, SearchResults, Subtitle, choose, parse_release


BASE_URL = "https://api.opensubtitles.com/api/v1"
MAX_SUBTITLE_BYTES = 256 * 1024
MAX_JSON_BYTES = 2 * 1024 * 1024
_USER_AGENT = "TorrentTVVietsub/0.1 (personal-local-client)"
_ALLOWED_HOSTS = {"api.opensubtitles.com", "vip-api.opensubtitles.com"}
_ALLOWED_DOWNLOAD_SUFFIX = ".opensubtitles.com"
_STAMP_SRT = re.compile(r"^\d{2}:\d{2}:\d{2},\d{3}$")
_STAMP_VTT = re.compile(r"^(?:\d{2}:)?\d{2}:\d{2}\.\d{3}$")


class SubtitleApiError(Exception):
    """Safe error: no API key, temporary download URL or subtitle text."""


@dataclass(frozen=True)
class Candidate:
    file_id: int
    subtitle: Subtitle


@dataclass(frozen=True)
class Discovery:
    media_key: tuple[str, str, int]
    results: SearchResults
    candidates: tuple[Candidate, ...]
    decision: Decision
    raw_rows: int = 0
    api_total: int | None = None
    # Counts only: do not return, persist or log provider filenames or dialog.
    parse_rejections: tuple[tuple[str, int], ...] = ()


@dataclass(frozen=True)
class Asset:
    file_id: int
    language: str
    fmt: str
    contents: bytes
    sha256: str
    cues: int


def _safe_https(url: str, *, api: bool) -> None:
    try:
        u = urllib.parse.urlsplit(url)
        hostname = (u.hostname or "").casefold()
        _ = u.port
    except (TypeError, ValueError) as exc:
        raise SubtitleApiError("UNTRUSTED_URL") from exc
    if (u.scheme != "https" or not hostname or u.username or u.password or u.fragment
            or (api and (hostname not in _ALLOWED_HOSTS or u.port not in (None, 443)))
            or (not api and not (hostname == "opensubtitles.com" or hostname.endswith(_ALLOWED_DOWNLOAD_SUFFIX)))):
        raise SubtitleApiError("UNTRUSTED_URL")
    if u.port not in (None, 443):
        raise SubtitleApiError("UNTRUSTED_URL")


class _SafeRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        _safe_https(newurl, api=False)
        prior = urllib.parse.urlsplit(req.full_url).hostname
        after = urllib.parse.urlsplit(newurl).hostname
        if prior != after and any(k.lower() in {"authorization", "api-key"} for k in req.headers):
            raise SubtitleApiError("CROSS_HOST_AUTH_REDIRECT")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def urllib_transport(method: str, url: str, headers: dict[str, str],
                     body: bytes | None, cap: int, *,
                     timeout_seconds: float = 15.0) -> bytes:
    """HTTPS-only transport; strict response cap and bounded redirects.

    The temporary provider link is *never* sent in an error message or log.
    """
    _safe_https(url, api=(method != "GET_BINARY"))
    action = "GET" if method == "GET_BINARY" else method
    req = urllib.request.Request(url, data=body, headers=headers, method=action)
    opener = urllib.request.build_opener(_SafeRedirects())
    try:
        # Per-socket timeout for the short VI probe. This is NOT a hard
        # end-to-end wall-clock deadline across DNS, redirects and reads.
        with opener.open(req, timeout=timeout_seconds) as res:
            data = res.read(cap + 1)
    except urllib.error.HTTPError as exc:
        status = exc.code
        if status == 429:
            raise SubtitleApiError("RATE_LIMITED_429") from None
        if status in (401, 403):
            raise SubtitleApiError("API_AUTH_DENIED") from None
        raise SubtitleApiError(f"API_HTTP_{status}") from None
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise SubtitleApiError("API_NETWORK_ERROR") from None
    if len(data) > cap:
        raise SubtitleApiError("RESPONSE_TOO_LARGE")
    return data


Transport = Callable[[str, str, dict[str, str], bytes | None, int], bytes]


def _json(payload: bytes) -> dict:
    try:
        value = json.loads(payload.decode("utf-8"))
    except (ValueError, UnicodeError) as exc:
        raise SubtitleApiError("BAD_API_JSON") from None
    if not isinstance(value, dict):
        raise SubtitleApiError("BAD_API_JSON")
    return value


def _fmt(file_name: str) -> str | None:
    """Source *hint* only, never proof of the downloadable subtitle bytes.

    Provider entries may omit a usable extension or name a non-SRT source.
    Rank these as 'provider'; conversion to SRT and content QA happen only
    after an explicit user-authorized POST /download.
    """
    if not isinstance(file_name, str) or not file_name.strip():
        return None
    if any(ord(c) < 32 for c in file_name) or "/" in file_name or "\\" in file_name:
        return None
    ext = file_name.rsplit(".", 1)[-1].lower()
    if ext in ("srt", "vtt"):
        return ext
    if ext in {"zip", "rar", "7z", "gz", "exe", "dll", "js", "html", "htm",
               "mkv", "mp4", "avi", "pdf"}:
        return None
    return "provider"


def parse_search_response(media: Media, body: bytes) -> Discovery:
    payload = _json(body)
    rows = payload.get("data")
    if not isinstance(rows, list) or len(rows) > 1000:
        raise SubtitleApiError("BAD_SEARCH_SCHEMA")
    out: list[Candidate] = []
    seen: set[int] = set()
    reasons = {
        "missing_attributes": 0, "unexpected_language": 0,
        "missing_files": 0, "invalid_file_entry": 0,
        "invalid_file_id": 0, "missing_file_name": 0,
        "unsupported_extension": 0, "duplicate_file_id": 0,
        "oversized_name": 0,
    }
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("attributes"), dict):
            reasons["missing_attributes"] += 1
            continue
        attrs = row["attributes"]
        language = attrs.get("language")
        if language not in ("vi", "en"):
            reasons["unexpected_language"] += 1
            continue
        files = attrs.get("files")
        if not isinstance(files, list) or not files:
            reasons["missing_files"] += 1
            continue
        release = attrs.get("release")
        for sub_file in files:
            if not isinstance(sub_file, dict):
                reasons["invalid_file_entry"] += 1
                continue
            file_id = sub_file.get("file_id")
            name = sub_file.get("file_name")
            if type(file_id) is not int or file_id <= 0:
                reasons["invalid_file_id"] += 1
                continue
            if file_id in seen:
                reasons["duplicate_file_id"] += 1
                continue
            if not isinstance(name, str) or not name:
                reasons["missing_file_name"] += 1
                continue
            if len(name) > 300 or (isinstance(release, str) and len(release) > 300):
                reasons["oversized_name"] += 1
                continue
            fmt = _fmt(name)
            if fmt is None:
                reasons["unsupported_extension"] += 1
                continue
            release_name = release if isinstance(release, str) and release.strip() else name
            seen.add(file_id)
            # API moviehash_match is only useful when the source hash was
            # separately verified on the selected media, not guessed from name.
            matched_hash = media.movie_hash if attrs.get("moviehash_match") is True else None
            out.append(Candidate(file_id, Subtitle(str(file_id), release_name, language,
                                                   fmt=fmt, movie_hash=matched_hash)))
    items = SearchResults(media.key, tuple(x.subtitle for x in out))
    total = payload.get("total_count")
    # Aggregate numeric diagnostics only: no raw provider payload or release titles.
    safe_total = total if type(total) is int and 0 <= total <= 10000000 else None
    return Discovery(media.key, items, tuple(out), choose(media, items),
                     raw_rows=len(rows), api_total=safe_total,
                     parse_rejections=tuple(reasons.items()))


def _milliseconds(stamp: str, fmt: str) -> int:
    pattern = _STAMP_SRT if fmt == "srt" else _STAMP_VTT
    if not pattern.fullmatch(stamp):
        raise SubtitleApiError("BAD_SUBTITLE_TIMELINE")
    numbers = [int(x) for x in re.split("[:,.]", stamp)]
    if len(numbers) == 4:
        h, m, s, ms = numbers
    else:
        h, m, s, ms = 0, *numbers
    if m > 59 or s > 59:
        raise SubtitleApiError("BAD_SUBTITLE_TIMELINE")
    return 1000 * (h * 3600 + m * 60 + s) + ms


def validate_timed_text(contents: bytes, fmt: str) -> int:
    if not contents or len(contents) > MAX_SUBTITLE_BYTES or fmt not in ("srt", "vtt"):
        raise SubtitleApiError("INVALID_SUBTITLE_SIZE_OR_FORMAT")
    try:
        text = contents.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise SubtitleApiError("SUBTITLE_NOT_UTF8") from None
    if "\0" in text or "<script" in text.lower() or "<!doctype" in text.lower():
        raise SubtitleApiError("UNSAFE_SUBTITLE_TEXT")
    text = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    if fmt == "vtt":
        if not (text == "WEBVTT" or text.startswith("WEBVTT\n")):
            raise SubtitleApiError("BAD_VTT_HEADER")
        blocks = re.split(r"\n[ \t]*\n", text)
        blocks = blocks[1:]
    else:
        blocks = re.split(r"\n[ \t]*\n", text)
    count = 0
    previous_start = -1
    for block in blocks:
        lines = [line.strip() for line in block.split("\n")]
        if not any(lines):
            continue
        if fmt == "vtt" and (lines[0].startswith(("NOTE", "STYLE", "REGION"))):
            continue
        timing = next((i for i, line in enumerate(lines[:2]) if "-->" in line), -1)
        if timing < 0 or timing + 1 >= len(lines):
            raise SubtitleApiError("BAD_SUBTITLE_TIMELINE")
        parts = lines[timing].split("-->")
        if len(parts) != 2:
            raise SubtitleApiError("BAD_SUBTITLE_TIMELINE")
        start = _milliseconds(parts[0].strip(), fmt)
        end = _milliseconds(parts[1].strip().split(" ", 1)[0], fmt)
        if end <= start or start < previous_start or not any(lines[timing + 1:]):
            raise SubtitleApiError("BAD_SUBTITLE_TIMELINE")
        previous_start = start
        count += 1
    if count == 0:
        raise SubtitleApiError("EMPTY_SUBTITLE")
    return count


def write_private_cache(directory: Path, media: Media, asset: Asset) -> Path:
    """On-demand file write only, keyed by *actual* video and subtitle provenance."""
    if asset.sha256 != hashlib.sha256(asset.contents).hexdigest():
        raise SubtitleApiError("BAD_CONTENT_DIGEST")
    if asset.cues != validate_timed_text(asset.contents, asset.fmt):
        raise SubtitleApiError("BAD_CUE_COUNT")
    key_data = json.dumps([*media.key, asset.file_id, asset.language, asset.sha256],
                          separators=(",", ":"), ensure_ascii=True).encode()
    filename = hashlib.sha256(key_data).hexdigest() + "." + asset.fmt
    root = Path(directory)
    if root.is_symlink():
        raise SubtitleApiError("UNSAFE_CACHE_ROOT")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    dest = root / filename
    try:
        fd = os.open(dest, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        if dest.is_symlink() or dest.read_bytes() != asset.contents:
            raise SubtitleApiError("CACHE_COLLISION")
        return dest
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(asset.contents)
    except BaseException:
        dest.unlink(missing_ok=True)
        raise
    return dest


class OpenSubtitles:
    def __init__(self, *, api_key: str, bearer: str | None = None,
                 transport: Transport = urllib_transport):
        if not isinstance(api_key, str) or not api_key.strip() or "\n" in api_key or "\r" in api_key:
            raise SubtitleApiError("API_KEY_NOT_CONFIGURED")
        if bearer is not None and (not isinstance(bearer, str) or not bearer.strip()
                                   or "\r" in bearer or "\n" in bearer):
            raise SubtitleApiError("INVALID_BEARER_TOKEN")
        self._api_key = api_key
        self._bearer = bearer
        self._transport = transport
        self._manual_post_attempted = False

    def _request(self, method: str, url: str, *, api: bool,
                 payload: dict | None = None,
                 timeout_seconds: float | None = None) -> bytes:
        _safe_https(url, api=api)
        headers = {"User-Agent": _USER_AGENT, "Accept": "application/json"}
        body = None
        if api:
            headers["Api-Key"] = self._api_key
            if self._bearer:
                headers["Authorization"] = "Bearer " + self._bearer
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        cap = MAX_JSON_BYTES if api else MAX_SUBTITLE_BYTES
        if timeout_seconds is not None:
            if type(timeout_seconds) not in (float, int) or not 1 <= timeout_seconds <= 15:
                raise SubtitleApiError("INVALID_SEARCH_TIMEOUT")
            # Keep five-argument injected test transports source compatible.
            # A real urllib GET can use the lower per-socket budget.
            if self._transport is urllib_transport:
                return urllib_transport(method, url, headers, body, cap,
                                        timeout_seconds=float(timeout_seconds))
        return self._transport(method, url, headers, body, cap)

    def search(self, media: Media, *, language: str,
               query_mode: str = "release", imdb_id: str | None = None,
               page: int = 1, timeout_seconds: float | None = None) -> Discovery:
        if language not in ("vi", "en"):
            raise SubtitleApiError("UNSUPPORTED_LANGUAGE")
        if type(page) is not int or page not in (1, 2):
            raise SubtitleApiError("UNSUPPORTED_PAGE")
        if query_mode not in ("release", "title", "imdb"):
            raise SubtitleApiError("UNSUPPORTED_QUERY_MODE")
        filename = re.split(r"[/\\]", media.filename)[-1]
        if len(filename) > 255 or any(ord(c) < 32 for c in filename):
            raise SubtitleApiError("BAD_MEDIA_FILENAME")
        release = parse_release(filename)
        if query_mode == "imdb":
            # The ID must be independently verified for the selected film.
            # Search by ID without restrictive year/query filters.
            if not isinstance(imdb_id, str) or not re.fullmatch(r"(?:tt)?[0-9]{1,12}", imdb_id):
                raise SubtitleApiError("INVALID_IMDB_ID")
            q = {"languages": language, "imdb_id": str(int(imdb_id.removeprefix("tt")))}
        else:
            # Release-first for exact scene names; title fallback may return
            # subtitles named after other encodes (still review before use).
            query = filename.rsplit(".", 1)[0] if query_mode == "release" else release.title
            if not query:
                raise SubtitleApiError("BAD_MEDIA_TITLE")
            q = {"languages": language, "query": query}
            if release.year is not None:
                q["year"] = str(release.year)
            if media.movie_hash is not None:
                q["moviehash"] = media.movie_hash.lower()
        if page > 1:
            q["page"] = str(page)
        url = BASE_URL + "/subtitles?" + urllib.parse.urlencode(sorted(q.items()))
        discovery = parse_search_response(
            media, self._request("GET", url, api=True,
                                 timeout_seconds=timeout_seconds))
        # Never let an unexpected EN row in a VI response trigger a download.
        candidates = tuple(c for c in discovery.candidates if c.subtitle.language == language)
        results = SearchResults(media.key, tuple(c.subtitle for c in candidates))
        return Discovery(media.key, results, candidates, choose(media, results),
                         raw_rows=discovery.raw_rows, api_total=discovery.api_total,
                         parse_rejections=discovery.parse_rejections)

    def download_manual_vi(self, media: Media, discovery: Discovery, *,
                           file_id: int, authorized: bool = False) -> Asset:
        """One explicit manual VI selection; not an automatic confidence override.

        Caller must display the candidate and receive in-session consent. The
        selected file must belong to this exact search and be ranked for the
        chosen movie title. Never choose by a stale or external file ID alone.
        Every call to POST /download can spend quota, even when QA later fails.
        """
        if authorized is not True:
            raise SubtitleApiError("MANUAL_CONSENT_REQUIRED")
        if (discovery.media_key != media.key or
                discovery.results.media_key != media.key or
                type(file_id) is not int or file_id <= 0):
            raise SubtitleApiError("MEDIA_BINDING_MISMATCH")
        matching = [item for item in discovery.candidates
                    if item.file_id == file_id and item.subtitle.language == "vi"]
        ranked = [item for item in discovery.decision.ranked
                  if item.subtitle_id == str(file_id) and item.language == "vi"
                  and "title" in item.evidence]
        if len(matching) != 1 or len(ranked) != 1:
            raise SubtitleApiError("NO_APPROVED_MANUAL_CANDIDATE")
        if self._manual_post_attempted:
            raise SubtitleApiError("MANUAL_DOWNLOAD_ALREADY_ATTEMPTED")
        # Latch BEFORE POST: a provider/network/QA failure never silently
        # triggers another quota-bearing request for this client session.
        self._manual_post_attempted = True
        # Request exactly one SRT output. The source file extension is only a
        # hint and cannot certify the returned byte stream or synchronization.
        response = _json(self._request("POST", BASE_URL + "/download", api=True,
                                       payload={"file_id": file_id, "sub_format": "srt"}))
        link = response.get("link")
        if not isinstance(link, str):
            raise SubtitleApiError("BAD_DOWNLOAD_SCHEMA")
        _safe_https(link, api=False)
        contents = self._request("GET_BINARY", link, api=False)
        count = validate_timed_text(contents, "srt")
        return Asset(file_id, "vi", "srt", contents,
                     hashlib.sha256(contents).hexdigest(), count)

    def download_manual_en(self, media: Media, discovery: Discovery, *,
                           file_id: int, authorized: bool = False) -> Asset:
        """Exactly one separately consented EN SRT download for translation.

        An EN release must be confidently matched and unambiguous. This does
        not prove subtitle/video synchronization and never invokes AI itself.
        """
        if authorized is not True:
            raise SubtitleApiError("MANUAL_CONSENT_REQUIRED")
        if (discovery.media_key != media.key or
                discovery.results.media_key != media.key or
                type(file_id) is not int or file_id <= 0):
            raise SubtitleApiError("MEDIA_BINDING_MISMATCH")
        decision = choose(media, discovery.results)
        if (decision.status != "EN_TRANSLATE" or decision.winner is None
                or decision.winner.subtitle_id != str(file_id)):
            raise SubtitleApiError("NO_CONFIDENT_EN_CANDIDATE")
        matching = [c for c in discovery.candidates if c.file_id == file_id
                    and c.subtitle.language == "en"]
        if len(matching) != 1:
            raise SubtitleApiError("NO_CONFIDENT_EN_CANDIDATE")
        if self._manual_post_attempted:
            raise SubtitleApiError("MANUAL_DOWNLOAD_ALREADY_ATTEMPTED")
        # Set latch before the first quota-bearing POST, including failures.
        self._manual_post_attempted = True
        response = _json(self._request("POST", BASE_URL + "/download", api=True,
                                       payload={"file_id": file_id,
                                                "sub_format": "srt"}))
        link = response.get("link")
        if not isinstance(link, str):
            raise SubtitleApiError("BAD_DOWNLOAD_SCHEMA")
        _safe_https(link, api=False)
        contents = self._request("GET_BINARY", link, api=False)
        cues = validate_timed_text(contents, "srt")
        return Asset(file_id, "en", "srt", contents,
                     hashlib.sha256(contents).hexdigest(), cues)

    def download_selected(self, media: Media, discovery: Discovery) -> Asset:
        """Exactly one explicit quota-incurring POST for a confident D1 winner."""
        if discovery.media_key != media.key or discovery.results.media_key != media.key:
            raise SubtitleApiError("MEDIA_BINDING_MISMATCH")
        decision = choose(media, discovery.results)
        if decision.status not in ("VI_MATCH", "EN_TRANSLATE") or decision.winner is None:
            raise SubtitleApiError("NO_APPROVED_DOWNLOAD")
        winner = decision.winner
        matching = [c for c in discovery.candidates if c.subtitle.subtitle_id == winner.subtitle_id]
        if len(matching) != 1 or str(matching[0].file_id) != winner.subtitle_id:
            raise SubtitleApiError("CANDIDATE_BINDING_MISMATCH")
        source_fmt = matching[0].subtitle.fmt
        # Unknown source extension is not SRT evidence. Ask provider to
        # convert specifically to SRT and still validate the actual bytes.
        payload = {"file_id": matching[0].file_id}
        if source_fmt == "provider":
            payload["sub_format"] = "srt"
        response = _json(self._request("POST", BASE_URL + "/download", api=True,
                                       payload=payload))
        link = response.get("link")
        if not isinstance(link, str):
            raise SubtitleApiError("BAD_DOWNLOAD_SCHEMA")
        _safe_https(link, api=False)
        contents = self._request("GET_BINARY", link, api=False)
        fmt = "srt" if source_fmt == "provider" else source_fmt
        count = validate_timed_text(contents, fmt)
        return Asset(matching[0].file_id, winner.language, fmt, contents,
                     hashlib.sha256(contents).hexdigest(), count)
