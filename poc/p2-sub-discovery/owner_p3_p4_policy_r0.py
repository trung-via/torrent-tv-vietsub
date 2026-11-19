"""Single-read inspection for the new Owner; immutable installed policy stays pinned."""
from __future__ import annotations

from pathlib import Path

from owner_p3_p4_private_policy import (
    PrivateP3P4Policy, _VIDEO_EXTENSIONS, _VI_SIDECARS, _inside,
)
from owner_selected_file_resolver import TorrServerSelectedFile, _one_basename


class R0PrivateP3P4Policy(PrivateP3P4Policy):
    def inspect_verified_file(self, profile: str, infohash: str, index: int,
                              selected: TorrServerSelectedFile) -> tuple[bool, str]:
        """One independently verified metadata read for both rights and VI.

        Never accept a TV-supplied path. The selected metadata is obtained by
        OwnerCurrentRedmiReader from its owner-configured localhost reader.
        """
        if (not self._enabled or profile != self._profile
                or not isinstance(selected, TorrServerSelectedFile)
                or type(index) is not int or selected.id != index
                or type(selected.length) is not int or selected.length <= 0):
            return False, "UNKNOWN"
        try:
            name = _one_basename(selected.path)
        except (ValueError, TypeError):
            return False, "UNKNOWN"
        if self._personal_stream_mode:
            if Path(name).suffix.lower() not in _VIDEO_EXTENSIONS:
                return False, "UNKNOWN"
            return True, self._stream_vi(profile, infohash, index)
        pin = self._pins.get((infohash, index))
        if (pin is None or not pin.rights_approved
                or selected.path != pin.torrserver_path):
            return False, "UNKNOWN"
        try:
            if pin.video_path is not None and (
                    name != pin.video_path.name
                    or not _inside(pin.video_path, self._root)
                    or not pin.video_path.is_file()
                    or pin.video_path.stat().st_size != selected.length):
                return False, "UNKNOWN"
        except OSError:
            return False, "UNKNOWN"
        if pin.stream_only:
            return True, self._stream_vi(profile, infohash, index)
        if pin.video_path is None:
            return True, "UNKNOWN"
        stem = pin.video_path.stem
        for suffix in _VI_SIDECARS:
            candidate = pin.video_path.parent / (stem + suffix)
            if candidate.is_symlink():
                return True, "UNKNOWN"
            if candidate.is_file():
                return True, "PRESENT"
        result = self._probe(pin.video_path)
        return True, result if result in ("PRESENT", "ABSENT") else "UNKNOWN"

    def _stream_vi(self, profile: str, infohash: str, index: int) -> str:
        if self._stream_probe is None:
            return "UNKNOWN"
        try:
            result = self._stream_probe(profile, infohash, index)
        except Exception:
            return "UNKNOWN"
        return result if result in ("PRESENT", "ABSENT") else "UNKNOWN"
