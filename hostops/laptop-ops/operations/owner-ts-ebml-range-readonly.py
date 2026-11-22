"""Bounded, content-silent MKV subtitle-cue probe over localhost TorrServer.

The diagnostic never writes subtitle text, torrent identifiers or media titles.
It never asks TorrServer to add/remove a torrent or calls a translation API.
"""
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener

BASE = "http://127.0.0.1:8090"
OPENER = build_opener(ProxyHandler({}))
START = time.monotonic()
LIMIT = START + 145
MAX_RANGE_REQUESTS = 300
MAX_RANGE_BYTES = 8 * 1024 * 1024
TEXT_CODECS = {"subrip", "ass", "ssa", "webvtt", "mov_text", "text"}
MATROSKA_TEXT = {"S_TEXT/UTF8", "S_TEXT/ASS", "S_TEXT/SSA", "S_TEXT/WEBVTT"}
EN = {"en", "eng", "en-us", "en-gb", "english"}


class DiagnosticStop(Exception):
    def __init__(self, code):
        self.code = code


def api(path, body=None, cap=262144):
    if time.monotonic() > LIMIT:
        raise DiagnosticStop("DEADLINE")
    url = BASE + path
    headers = {"Cache-Control": "no-store"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = Request(url, data=body, headers=headers, method="POST" if body else "GET")
    try:
        with OPENER.open(req, timeout=3) as resp:
            if resp.status != 200:
                raise DiagnosticStop("API_HTTP")
            data = resp.read(cap + 1)
            if not data or len(data) > cap:
                raise DiagnosticStop("API_SIZE")
            return json.loads(data)
    except (HTTPError, URLError, OSError, ValueError):
        raise DiagnosticStop("API_UNAVAILABLE") from None


def recent_owner_selections():
    # The OwnerBridge event already binds the file to its TorrServer hash,
    # index and configured profile. Read only the owner's own local state;
    # never publish the event, filename, profile or fingerprint.
    base = os.environ.get("LOCALAPPDATA")
    if not base:
        own_home = os.environ.get("USERPROFILE")
        if not own_home:
            raise DiagnosticStop("OWNER_ENV_UNAVAILABLE")
        base = str(Path(own_home) / "AppData" / "Local")
    owner = Path(base) / "TorrentTVVietsub" / "OwnerBridge"
    try:
        if not (owner / "p3-p4-policy.json").is_file():
            raise DiagnosticStop("OWNER_POLICY_MISSING")
        policy = json.loads((owner / "p3-p4-policy.json").read_text("utf-8"))
        profile = policy.get("profile_id")
        if (policy.get("enabled") is not True or not isinstance(profile, str)
                or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", profile)):
            raise DiagnosticStop("OWNER_POLICY_UNAVAILABLE")
        inbox = owner / "inbox"
        if not inbox.is_dir():
            raise DiagnosticStop("OWNER_INBOX_MISSING")
        events = [p for suffix in ("blocked", "done", "review", "pending", "json")
                  for p in inbox.glob("event-*." + suffix)
                  if p.is_file() and not p.is_symlink()
                  and 0 < p.stat().st_size <= 1024
                  and 0 <= time.time() - p.stat().st_mtime <= 2 * 86400]
        events.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        selection = []
        for path in events[:128]:
            try:
                doc = json.loads(path.read_text("utf-8"))
            except (ValueError, UnicodeError):
                continue
            if not isinstance(doc, dict):
                continue
            name, fp, event_id = (doc.get("selected_video_filename"),
                                  doc.get("source_fingerprint"), doc.get("event_id"))
            if (isinstance(name, str) and 0 < len(name) <= 255
                    and "/" not in name and "\\" not in name
                    and isinstance(fp, str) and re.fullmatch("[0-9a-f]{64}", fp)
                    and isinstance(event_id, str)
                    and re.fullmatch("[0-9a-f]{32}", event_id)
                    and path.name == "event-" + event_id + path.suffix):
                selection.append((name, fp))
        if not selection:
            raise DiagnosticStop("OWNER_EVENT_UNAVAILABLE")
        return profile, selection
    except PermissionError:
        raise DiagnosticStop("OWNER_CONTEXT_DENIED") from None
    except (OSError, ValueError, TypeError):
        raise DiagnosticStop("OWNER_CONTEXT_INVALID") from None


def candidate():
    profile, selections = recent_owner_selections()
    torrents = api("/torrents", b'{"action":"list"}', cap=524288)
    if not isinstance(torrents, list) or len(torrents) > 256:
        raise DiagnosticStop("LIST_INVALID")
    choices = []
    for torrent in torrents:
        if not isinstance(torrent, dict):
            continue
        hashval = torrent.get("hash")
        if not isinstance(hashval, str) or not re.fullmatch("[0-9a-f]{40}|[0-9a-f]{64}", hashval):
            continue
        files = torrent.get("file_stats")
        if not isinstance(files, list) or not files:
            try:
                files = json.loads(torrent.get("data", "{}"))["TorrServer"]["Files"]
            except (KeyError, ValueError, TypeError):
                continue
        if not isinstance(files, list) or len(files) > 4096:
            continue
        for file in files:
            if not isinstance(file, dict):
                continue
            idx, path = file.get("id"), file.get("path")
            if (type(idx) is int and 0 <= idx < 4096 and isinstance(path, str)
                    and path.lower().endswith(".mkv")):
                basename = path.replace("\\", "/").rsplit("/", 1)[-1]
                digest = hashlib.sha256(
                    "\0".join((profile, hashval, str(idx))).encode()).hexdigest()
                if (basename, digest) in selections:
                    choices.append((hashval, idx, basename, digest))
    if not choices:
        raise DiagnosticStop("OWNER_SELECTION_NOT_FOUND")
    for name, fp in selections:
        matches = {(tor, idx) for tor, idx, basename, digest in choices
                   if name == basename and fp == digest}
        if len(matches) > 1:
            raise DiagnosticStop("OWNER_SELECTION_AMBIGUOUS")
        if len(matches) == 1:
            hashval, idx = next(iter(matches))
            doc = api("/ffp/" + hashval + "/" + str(idx), cap=131072)
            streams = doc.get("streams") if isinstance(doc, dict) else None
            if not isinstance(streams, list) or len(streams) > 128:
                raise DiagnosticStop("FFP_INVALID")
            en_text = [s for s in streams if isinstance(s, dict)
                       and s.get("codec_type") == "subtitle"
                       and s.get("codec_name") in TEXT_CODECS
                       and isinstance(s.get("tags"), dict)
                       and str(s["tags"].get("language", "")).lower() in EN]
            if not en_text:
                raise DiagnosticStop("OWNER_EN_TEXT_UNAVAILABLE")
            return hashval, idx, len(en_text)
    raise DiagnosticStop("OWNER_SELECTION_NOT_FOUND")


def vint(buf, offset, *, size):
    if offset >= len(buf):
        raise DiagnosticStop("TRUNCATED_EBML")
    first = buf[offset]
    if first == 0:
        raise DiagnosticStop("INVALID_VINT")
    width = 9 - first.bit_length()
    if width > (8 if size else 4) or offset + width > len(buf):
        raise DiagnosticStop("INVALID_VINT")
    raw = int.from_bytes(buf[offset:offset + width], "big")
    if size:
        raw &= (1 << (width * 7)) - 1
        if raw == (1 << (width * 7)) - 1:
            raise DiagnosticStop("UNKNOWN_ELEMENT_SIZE")
    return raw, width


def children(data):
    position = 0
    while position < len(data):
        eid, ilen = vint(data, position, size=False)
        length, slen = vint(data, position + ilen, size=True)
        start = position + ilen + slen
        end = start + length
        if end > len(data):
            raise DiagnosticStop("TRUNCATED_EBML")
        yield eid, data[start:end], position
        position = end


def fields(data):
    return {eid: value for eid, value, _ in children(data)}


def number(data):
    return int.from_bytes(data, "big")


class Ranges:
    def __init__(self, hashval, index):
        self.path = "/play/" + hashval + "/" + str(index)
        self.total = None
        self.requests = 0
        self.bytes = 0

    def read(self, at, length):
        if (time.monotonic() > LIMIT or self.requests >= MAX_RANGE_REQUESTS
                or self.bytes + length > MAX_RANGE_BYTES or
                at < 0 or not 0 < length <= 262144):
            raise DiagnosticStop("RANGE_BUDGET")
        end = at + length - 1
        request = Request(BASE + self.path, headers={
            "Range": f"bytes={at}-{end}", "Connection": "close",
            "Cache-Control": "no-store"
        })
        self.requests += 1
        # The first MKV header is usually cached locally. A distant SeekHead
        # target (often Cues near EOF) may require fresh torrent pieces;
        # allow one bounded 10-second wait without retrying the same effect.
        timeout = 10 if at >= 262144 else 3
        try:
            with OPENER.open(request, timeout=timeout) as response:
                if response.status != 206:
                    raise DiagnosticStop("RANGE_NOT_206")
                value = response.headers.get("Content-Range", "")
                match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", value)
                if not match or int(match[1]) != at or int(match[2]) > end:
                    raise DiagnosticStop("RANGE_MISMATCH")
                total = int(match[3])
                if total <= 0 or (self.total is not None and self.total != total):
                    raise DiagnosticStop("FILE_IDENTITY_DRIFT")
                self.total = total
                content = response.read(length + 1)
                if len(content) != int(match[2]) - at + 1:
                    raise DiagnosticStop("RANGE_SHORT_READ")
                self.bytes += len(content)
                return content
        except HTTPError as exc:
            code = exc.code
            if code in (400, 401, 403, 404, 408, 416, 429,
                        500, 502, 503, 504):
                raise DiagnosticStop("RANGE_HTTP_" + str(code)) from None
            raise DiagnosticStop("RANGE_HTTP_OTHER") from None
        except URLError as exc:
            if isinstance(exc.reason, TimeoutError):
                raise DiagnosticStop("RANGE_TIMEOUT") from None
            raise DiagnosticStop("RANGE_CONNECTION_ERROR") from None
        except TimeoutError:
            raise DiagnosticStop("RANGE_TIMEOUT") from None
        except OSError:
            raise DiagnosticStop("RANGE_IO_ERROR") from None

    def element(self, at, maximum):
        header = self.read(at, 16)
        eid, ilen = vint(header, 0, size=False)
        length, slen = vint(header, ilen, size=True)
        if length > maximum:
            raise DiagnosticStop("ELEMENT_TOO_LARGE")
        offset = at + ilen + slen
        content = bytearray()
        while len(content) < length:
            next_size = min(262144, length - len(content))
            content.extend(self.read(offset + len(content), next_size))
        return eid, bytes(content), offset

    def small_element(self, at, maximum=16384):
        # One Range request for the complete small subtitle block in the common
        # case, including its EBML ID/size. Never fetch a full video Cluster.
        probe = self.read(at, 768)
        eid, ilen = vint(probe, 0, size=False)
        length, slen = vint(probe, ilen, size=True)
        if length > maximum:
            raise DiagnosticStop("ELEMENT_TOO_LARGE")
        payload_at = ilen + slen
        required = payload_at + length
        if required <= len(probe):
            return eid, probe[payload_at:required]
        remainder = bytearray(probe[payload_at:])
        while len(remainder) < length:
            next_size = min(16384, length - len(remainder))
            remainder.extend(self.read(at + payload_at + len(remainder), next_size))
        return eid, bytes(remainder)


def parse_root(reader):
    prefix = reader.read(0, 262144)
    pos = 0
    ebml_id, ilen = vint(prefix, pos, size=False)
    size, slen = vint(prefix, pos + ilen, size=True)
    if ebml_id != 0x1A45DFA3:
        raise DiagnosticStop("NOT_MATROSKA")
    pos += ilen + slen + size
    segment_id, ilen = vint(prefix, pos, size=False)
    # Segment may use an unknown-size VINT, so only decode its width.
    first = prefix[pos + ilen]
    swidth = 9 - first.bit_length()
    if segment_id != 0x18538067 or swidth > 8:
        raise DiagnosticStop("SEGMENT_INVALID")
    segment_base = pos + ilen + swidth
    seeks = {"_segment_base": segment_base}
    offset = segment_base
    for _ in range(24):
        if offset >= len(prefix) - 16:
            break
        eid, elen = vint(prefix, offset, size=False)
        length, slen = vint(prefix, offset + elen, size=True)
        payload_at = offset + elen + slen
        if eid == 0x114D9B74:
            if length > 131072:
                raise DiagnosticStop("SEEKHEAD_TOO_LARGE")
            for sid, sub, _ in children(prefix[payload_at:payload_at + length]):
                if sid == 0x4DBB:
                    seek = fields(sub)
                    if 0x53AB in seek and 0x53AC in seek:
                        seeks[number(seek[0x53AB])] = segment_base + number(seek[0x53AC])
        if eid == 0x1F43B675:
            break
        offset = payload_at + length
    if 0x1654AE6B not in seeks or 0x1C53BB6B not in seeks:
        raise DiagnosticStop("INDEX_MISSING")
    return seeks


def parse_track(reader, seeks):
    eid, payload, _ = reader.element(seeks[0x1654AE6B], 262144)
    if eid != 0x1654AE6B:
        raise DiagnosticStop("TRACKS_INVALID")
    tracks = []
    for ident, body, _ in children(payload):
        if ident != 0xAE:
            continue
        f = fields(body)
        if number(f.get(0x83, b"\0")) != 17:
            continue
        lang = f.get(0x22B59D, f.get(0x22B59C, b"und")).decode("utf-8", "replace").lower()
        codec = f.get(0x86, b"").decode("ascii", "replace")
        if lang in EN and codec in MATROSKA_TEXT and 0xD7 in f:
            tracks.append((number(f[0xD7]), codec, number(f.get(0x88, b"\1")),
                           number(f.get(0x55AA, b"\0"))))
    nonforced = [t for t in tracks if t[3] == 0]
    defaults = [t for t in nonforced if t[2] == 1]
    if not nonforced:
        raise DiagnosticStop("EN_TRACK_UNAVAILABLE")
    # SAMPLE_ONLY: an ambiguous EN track must never be promoted to the P2
    # translation source. Use the lowest non-forced TrackNumber strictly for
    # measuring whether MKV Cues point to real text blocks.
    pool = defaults if len(defaults) == 1 else nonforced
    return min(pool, key=lambda t: t[0]), len(tracks)


def parse_cues(reader, seeks, track):
    eid, payload, _ = reader.element(seeks[0x1C53BB6B], 2097152)
    if eid != 0x1C53BB6B:
        raise DiagnosticStop("CUES_INVALID")
    cues = []
    for ident, point, _ in children(payload):
        if ident != 0xBB:
            continue
        outer = fields(point)
        if 0xB3 not in outer:
            continue
        stamp = number(outer[0xB3])
        for sub_id, body, _ in children(point):
            if sub_id != 0xB7:
                continue
            row = fields(body)
            if 0xF7 not in row or number(row[0xF7]) != track:
                continue
            if 0xF1 not in row:
                continue
            cues.append((stamp, number(row[0xF1]),
                         number(row[0xF0]) if 0xF0 in row else None,
                         number(row[0xB2]) if 0xB2 in row else None))
    return cues


def has_text_block(reader, cluster_at, relative, track, cluster_headers):
    if cluster_at not in cluster_headers:
        header = reader.read(cluster_at, 16)
        cluster_id, ilen = vint(header, 0, size=False)
        _, slen = vint(header, ilen, size=True)
        if cluster_id != 0x1F43B675:
            return False
        cluster_headers[cluster_at] = ilen + slen
    cluster_data_start = cluster_at + cluster_headers[cluster_at]
    # Matroska CueRelativePosition is relative to Cluster payload. Retain a
    # fallback for differing source behavior, but avoid two probes per cue.
    for start in (cluster_data_start + relative, cluster_at + relative):
        try:
            eid, payload = reader.small_element(start)
        except DiagnosticStop:
            continue
        if eid == 0xA0:
            payload = fields(payload).get(0xA1, b"")
        elif eid != 0xA3:
            continue
        if not payload:
            continue
        try:
            num, width = vint(payload, 0, size=True)
        except DiagnosticStop:
            continue
        content = payload[width + 3:]
        if (num == track and content and len(content) <= 8192
                and content.decode("utf-8", "strict").strip()):
            return True
    return False


def main():
    row = dict(state="NOT_RUN", identity="UNVERIFIED", en_ffp=0,
               en_mkv=0, cues_indexed=0, cues_relative=0, cues_verified=0,
               bytes=0, requests=0, ms=0, first_ten_ms=0)
    reader = None
    try:
        hashval, idx, count = candidate()
        row["identity"] = "OWNER_EVENT_MATCH"
        row["en_ffp"] = count
        reader = Ranges(hashval, idx)
        seeks = parse_root(reader)
        selected, found = parse_track(reader, seeks)
        row["en_mkv"] = found
        cues = parse_cues(reader, seeks, selected[0])
        row["cues_indexed"] = min(30000, len(cues))
        row["cues_relative"] = min(30000, sum(r is not None for _, _, r, _ in cues))
        if not cues:
            raise DiagnosticStop("EN_CUES_MISSING")
        previous = -1
        cluster_headers = {}
        for stamp, cluster, relative, duration in cues[:120]:
            if time.monotonic() > LIMIT:
                break
            if stamp < previous:
                raise DiagnosticStop("CUES_UNSORTED")
            previous = stamp
            if relative is not None and has_text_block(reader, seeks.get("_segment_base", 0) + cluster,
                                                        relative, selected[0], cluster_headers):
                row["cues_verified"] += 1
                if row["cues_verified"] == 10:
                    row["first_ten_ms"] = int((time.monotonic() - START) * 1000)
        row["state"] = "TEXT_CUES_VERIFIED" if row["cues_verified"] >= 120 else (
            "INDEX_FOUND_TEXT_PARTIAL" if row["cues_verified"] else "INDEX_FOUND_TEXT_UNVERIFIED")
    except DiagnosticStop as exc:
        row["state"] = exc.code
    except (ValueError, UnicodeError, KeyError, TypeError):
        row["state"] = "PARSER_ERROR"
    finally:
        if reader is not None:
            row["bytes"] = min(reader.bytes, MAX_RANGE_BYTES)
            row["requests"] = reader.requests
        row["ms"] = min(160000, int((time.monotonic() - START) * 1000))
        print("HOSTOPS_EBML_" + json.dumps(row, separators=(",", ":")))


if __name__ == "__main__":
    main()
