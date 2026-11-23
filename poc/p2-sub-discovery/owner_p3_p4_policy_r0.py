"""Single-read selected-file eligibility for external Vietsub discovery.

The explicit AI request is independent of embedded MKV subtitle inventory.
P3/P4 use ``ABSENT`` to mean there is no *blocking* local-VI reuse on this
external-discovery path, not that the torrent has no Vietnamese subtitle track.
"""
from __future__ import annotations

from pathlib import Path

from owner_p3_p4_private_policy import (
    PrivateP3P4Policy, _VIDEO_EXTENSIONS, _inside,
)
from owner_selected_file_resolver import TorrServerSelectedFile, _one_basename


class R0PrivateP3P4Policy(PrivateP3P4Policy):
    def inspect_verified_file(self, profile: str, infohash: str, index: int,
                              selected: TorrServerSelectedFile) -> tuple[bool, str]:
        """One independently verified metadata read for external subtitle work.

        Never accept a TV-supplied path. The selected metadata is obtained by
        OwnerCurrentRedmiReader from its owner-configured localhost reader.
        Existing embedded/local Vietnamese tracks must not suppress an
        explicit AI translation or the separate downloaded-VI candidate.
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
            return True, "ABSENT"
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
        # This branch is about *external* candidates, not local-sub reuse.
        # Never block P3 on an /ffp track probe, a bundled MKV track, or a
        # sidecar left by an older playback session. P4's per-media revision
        # and P2's source checkpoint remain independent of this gate.
        return True, "ABSENT"
