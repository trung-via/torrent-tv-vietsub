"""Additive rolling P2 callback to the existing verified V3 processor.

Every P2 checkpoint is bound again to the current authenticated TV session,
Owner localhost TorrServer selected file, and unchanged source fingerprint.
An unavailable TV stops P4 publication; it never repeats a paid model call.
"""
from __future__ import annotations

from owner_r2_progressive_registry import R2OwnerProgressiveRegistry
from owner_r2_progressive_worker import R2ProgressiveWorker
from owner_selected_file_resolver import (
    CurrentPlaying, TorrServerSelectedFile, _fingerprint, _one_basename,
)
from verified_v3_processor import (
    VerifiedV3Processor, subtitle_lookup_identity,
)


class R2VerifiedV3Processor(VerifiedV3Processor):
    def __init__(self, *, progressive_registry: R2OwnerProgressiveRegistry,
                 **kwargs):
        if not isinstance(progressive_registry, R2OwnerProgressiveRegistry):
            raise ValueError("P4_ROLLING_REGISTRY_REQUIRED")
        super().__init__(**kwargs)
        self.progressive_registry = progressive_registry

    def selected_media(self, video_filename: str, *,
                       source_fingerprint: str | None = None,
                       tv_session_id: str | None = None) -> object:
        worker = getattr(self.flow, "worker", None)
        if not isinstance(worker, R2ProgressiveWorker):
            return super().selected_media(
                video_filename, source_fingerprint=source_fingerprint,
                tv_session_id=tv_session_id)

        def publish_verified(handoff, revision) -> None:
            current = self.read_current()
            if (not isinstance(current, CurrentPlaying)
                    or current.tv_session_id != tv_session_id
                    or _fingerprint(current.server_id, current.torrent_hash,
                                    current.file_index) != source_fingerprint):
                raise ValueError("P4_ROLLING_TV_SESSION_CHANGED")
            selected = self.read_server(
                current.server_id, current.torrent_hash.lower(),
                current.file_index)
            if (not isinstance(selected, TorrServerSelectedFile)
                    or selected.id != current.file_index
                    or type(selected.length) is not int or selected.length <= 0
                    or _one_basename(selected.path) != current.video_name):
                raise ValueError("P4_ROLLING_TORRSERVER_FILE_CHANGED")
            lookup = subtitle_lookup_identity(current, selected)
            if lookup.media.filename != video_filename or not lookup.title_hint:
                raise ValueError("P4_ROLLING_SELECTED_MEDIA_CHANGED")
            self.progressive_registry.publish_worker_revision(
                media=lookup.media, source_fingerprint=source_fingerprint,
                tv_session_id=tv_session_id, flow=self.flow,
                handoff=handoff, revision=revision)

        with worker.bind(publish_verified):
            return super().selected_media(
                video_filename, source_fingerprint=source_fingerprint,
                tv_session_id=tv_session_id)
