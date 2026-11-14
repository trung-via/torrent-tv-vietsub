"""Offline exact selected-file resolver contract: synthetic owner media only."""
from __future__ import annotations

from dataclasses import replace
import hashlib
from pathlib import Path
import tempfile
import unittest

from owner_selected_file_resolver import (
    CurrentPlaying, TorrServerSelectedFile, OwnerPinnedFiles,
    SelectedFileResolveError, resolve_selected_local_source, _fingerprint,
)
from local_en_direct import find_local_english
from test_automatic_vietsub_flow import srt


MOVIE = "Example.Movie.2026.1080p.WEB.x265-TEST.mkv"
TORRENT_PATH = "Season1/" + MOVIE
HASH = "a" * 40
SERVER = "owner-server-A"


class ResolverTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.media = self.root / "media"
        self.media.mkdir()
        self.folder = self.media / "Season1"
        self.folder.mkdir()
        self.video = self.folder / MOVIE
        self.video.write_bytes(b"not real video -- synthetic source")
        self.sidecar = self.folder / (Path(MOVIE).stem + ".en.srt")
        self.sidecar.write_bytes(srt(3))
        self.snapshot = CurrentPlaying(
            kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
            server_id=SERVER, tv_session_id="tv-current-1",
            torrent_hash=HASH, file_index=3, video_name=MOVIE,
            owner_auto_enabled=True, viewer_choice="ON",
            media_rights_approved=True, local_vi_state="ABSENT")
        self.record = TorrServerSelectedFile(
            id=3, path=TORRENT_PATH, length=self.video.stat().st_size)
        self.owner = OwnerPinnedFiles(
            video_path=self.video, english_sidecar_path=None,
            video_file_complete=True)
        self.calls = []

    def resolve(self, *, state=None, record=None, owner=None, fp=None,
                name=MOVIE, reader=None):
        state = state or self.snapshot
        record = record or self.record
        owner = self.owner if owner is None else owner
        fp = fp or _fingerprint(SERVER, HASH, 3)
        def tv_reader():
            self.calls.append("tv")
            return state
        def server_reader(server, hash_, index):
            self.calls.append("server")
            self.assertEqual((server, hash_, index),
                             (state.server_id, state.torrent_hash.lower(), state.file_index))
            return record
        def local_reader(server, hash_, index, path):
            self.calls.append("owner")
            self.assertEqual((server, hash_, index, path),
                             (state.server_id, state.torrent_hash.lower(),
                              state.file_index, record.path))
            return owner
        return resolve_selected_local_source(
            requested_name=name, source_fingerprint=fp,
            private_media_root=self.media,
            read_verified_current_playback=reader or tv_reader,
            read_verified_torrserver_file=server_reader,
            locate_owner_pinned_files=local_reader)

    def test_exact_selected_file_gets_one_english_sidecar_without_scan(self):
        resolved = self.resolve()
        self.assertEqual(self.calls, ["tv", "server", "owner"])
        self.assertEqual((resolved.server_id, resolved.torrent_hash,
                          resolved.file_index, resolved.video_name),
                         (SERVER, HASH, 3, MOVIE))
        self.assertEqual(resolved.en_sidecar_path, self.sidecar)
        receipt = find_local_english(resolved, cache_root=self.root / "private_cache")
        self.assertEqual((receipt.asset.cues, receipt.source_kind),
                         (3, "SIDECAR_SRT"))

    def test_exact_source_fingerprint_matches_p3_gate_spec(self):
        expected = hashlib.sha256(("\x00".join((SERVER, HASH, "3"))).encode()).hexdigest()
        self.assertEqual(_fingerprint(SERVER, HASH, 3), expected)

    def test_same_name_other_torrent_cannot_take_owner_mapping(self):
        wrong = replace(self.snapshot, torrent_hash="b" * 40)
        with self.assertRaisesRegex(SelectedFileResolveError, "FINGERPRINT_MISMATCH"):
            self.resolve(state=wrong)
        self.assertEqual(self.calls, ["tv"])

    def test_stale_episode_and_wrong_tv_session_block_before_owner_disk(self):
        for modified in (replace(self.snapshot, file_index=4),
                         replace(self.snapshot, active=False),
                         replace(self.snapshot, attested=False)):
            self.calls.clear()
            with self.subTest(modified=modified):
                with self.assertRaises(SelectedFileResolveError):
                    self.resolve(state=modified)
                self.assertEqual(self.calls, ["tv"])

    def test_missing_or_incorrect_torrserver_file_blocks_before_disk(self):
        for bad in (replace(self.record, id=4),
                    replace(self.record, path="Season2/" + MOVIE.replace("TEST", "DIFF")),
                    replace(self.record, length=-1),
                    replace(self.record, path="../" + MOVIE),
                    replace(self.record, path="C:/owner/" + MOVIE)):
            self.calls.clear()
            with self.subTest(bad=bad):
                with self.assertRaises(SelectedFileResolveError):
                    self.resolve(record=bad)
                self.assertEqual(self.calls, ["tv", "server"])

    def test_owner_off_or_viewer_off_other_or_vi_present_never_read_disk(self):
        for fields in ({"viewer_choice": "OFF"}, {"viewer_choice": "OTHER"},
                       {"owner_auto_enabled": False},
                       {"local_vi_state": "PRESENT"},
                       {"local_vi_state": "UNKNOWN"},
                       {"media_rights_approved": False}):
            self.calls.clear()
            with self.subTest(fields=fields):
                with self.assertRaisesRegex(SelectedFileResolveError, "GATE_BLOCKED"):
                    self.resolve(state=replace(self.snapshot, **fields))
                self.assertEqual(self.calls, ["tv"])

    def test_incomplete_movie_allows_sidecar_but_no_embedded_probe(self):
        out = self.resolve(owner=replace(self.owner, video_file_complete=False))
        self.assertEqual(out.en_sidecar_path, self.sidecar)
        self.assertFalse(out.video_file_complete)

    def test_complete_local_file_size_must_match_server_length(self):
        with self.assertRaisesRegex(SelectedFileResolveError, "SIZE_MISMATCH"):
            self.resolve(record=replace(self.record, length=123456))

    def test_no_owner_local_map_is_explicit_fallback(self):
        def no_binding(*_):
            return None
        result = resolve_selected_local_source(
            requested_name=MOVIE,
            source_fingerprint=_fingerprint(SERVER, HASH, 3),
            private_media_root=self.media,
            read_verified_current_playback=lambda: self.snapshot,
            read_verified_torrserver_file=lambda *args: self.record,
            locate_owner_pinned_files=no_binding)
        self.assertIsNone(result)

    def test_no_local_movie_and_exact_sidecar_owner_pin_can_work(self):
        out = self.resolve(owner=OwnerPinnedFiles(
            english_sidecar_path=self.sidecar))
        self.assertIsNone(out.video_path)
        self.assertEqual(out.en_sidecar_path, self.sidecar)

    def test_wrong_sidecar_or_outside_root_fails_closed(self):
        wrong = self.folder / "Other.Movie.en.srt"
        wrong.write_bytes(srt(1))
        with self.assertRaisesRegex(SelectedFileResolveError, "SIDECAR_NAME_MISMATCH"):
            self.resolve(owner=OwnerPinnedFiles(
                english_sidecar_path=wrong))
        outside = self.root / "secrets.en.srt"
        outside.write_bytes(srt(1))
        with self.assertRaisesRegex(SelectedFileResolveError, "UNTRUSTED_PRIVATE_PATH"):
            self.resolve(owner=OwnerPinnedFiles(
                english_sidecar_path=outside))

    def test_multiple_exact_english_files_holds_not_arbitrarily_choose(self):
        other = self.folder / (Path(MOVIE).stem + ".eng.srt")
        other.write_bytes(srt(2))
        with self.assertRaisesRegex(SelectedFileResolveError, "AMBIGUOUS_LOCAL_EN"):
            self.resolve()

    def test_selected_name_must_match_current_tv_media(self):
        with self.assertRaisesRegex(SelectedFileResolveError, "SELECTED_MEDIA_MISMATCH"):
            self.resolve(name=MOVIE.replace("TEST", "WRONG"))

    def test_error_readers_sanitized_without_paths_or_network(self):
        def nope():
            raise RuntimeError("private secrets from some source")
        with self.assertRaisesRegex(SelectedFileResolveError, "^RESOLVER_PLAYBACK_READER_UNAVAILABLE$"):
            self.resolve(reader=nope)

    def test_symlinked_owner_file_refused(self):
        alias = self.folder / ("alias" + self.video.suffix)
        try:
            alias.symlink_to(self.video)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks unavailable")
        with self.assertRaisesRegex(SelectedFileResolveError, "UNTRUSTED_PRIVATE_PATH"):
            self.resolve(owner=OwnerPinnedFiles(video_path=alias))


if __name__ == "__main__":
    unittest.main()
