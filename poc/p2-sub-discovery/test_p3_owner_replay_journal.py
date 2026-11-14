"""P3 signed Redmi restart-durable owner anti-replay: synthetic only."""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from p3_owner_replay_journal import OwnerReplayJournal, ReplayJournalRejected
from p3_redmi_current_state import (
    SignedRedmiStateCache, RedmiStateRejected, sign_synthetic_state,
)
from p3_signed_playback_signal import (
    SignedPlaybackVerifier, SignedPlaybackError, sign_synthetic_event,
)
from p3_owner_state_wiring import compose_owner_redmi_status
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader
from paired_activation import PairedActivation

SECRET = bytes(range(32))
TIME = 1_800_000_000_000
BOOT_A = "a" * 32
BOOT_B = "b" * 32
NONCE_1 = "c" * 32
NONCE_2 = "d" * 32
HASH = "e" * 40
SESSION = "f" * 32


def state(*, boot_id=BOOT_A, sequence=1, nonce=NONCE_1,
          sent_at_ms=TIME, active=True, subtitle_choice="ON"):
    return sign_synthetic_state(
        SECRET, boot_id=boot_id, sequence=sequence,
        kind="PLAY_REQUEST_ACCEPTED", tv_session_id=SESSION,
        torrent_hash=HASH, file_index=2, active=active,
        subtitle_choice=subtitle_choice, sent_at_ms=sent_at_ms,
        nonce=nonce)


def selection(*, nonce=NONCE_1, sent_at_ms=TIME):
    return sign_synthetic_event(
        SECRET, kind="PLAY_REQUEST_ACCEPTED",
        tv_session_id=SESSION, torrent_hash=HASH, file_index=2,
        sent_at_ms=sent_at_ms, nonce=nonce)


class DurableReplayTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="p3-replay-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve() / "private-owner"

    def test_state_nonce_and_sequence_survive_full_python_object_restart(self):
        a = SignedRedmiStateCache(SECRET, journal=OwnerReplayJournal(self.root))
        self.assertEqual(a.receive(state(), now_ms=TIME,
                                   monotonic_s=100).sequence, 1)
        path = self.root / "p3-replay" / "ledger.sqlite3"
        self.assertTrue(path.is_file())
        # A new instance may NOT infer active TV from a persisted status.
        b = SignedRedmiStateCache(SECRET, journal=OwnerReplayJournal(self.root))
        with self.assertRaisesRegex(RedmiStateRejected, "STALE_OR_MISSING"):
            b.read_fresh(monotonic_s=101)
        with self.assertRaisesRegex(RedmiStateRejected, "DURABLE_REPLAY"):
            b.receive(state(), now_ms=TIME, monotonic_s=102)
        # No falling back to memory-only acceptance after a rejected packet.
        with self.assertRaisesRegex(RedmiStateRejected, "STALE_OR_MISSING"):
            b.read_fresh(monotonic_s=103)
        self.assertEqual(b.receive(
            state(sequence=2, nonce=NONCE_2, sent_at_ms=TIME+100),
            now_ms=TIME+100, monotonic_s=104).sequence, 2)
        c = SignedRedmiStateCache(SECRET, journal=OwnerReplayJournal(self.root))
        with self.assertRaisesRegex(RedmiStateRejected, "DURABLE_REPLAY"):
            c.receive(state(sequence=2, nonce="1"*32, sent_at_ms=TIME+200),
                      now_ms=TIME+200, monotonic_s=105)

    def test_selection_replay_and_timestamp_highwater_survive_restart(self):
        one = SignedPlaybackVerifier(SECRET, journal=OwnerReplayJournal(self.root))
        self.assertEqual(one.verify(selection(), now_ms=TIME).file_index, 2)
        two = SignedPlaybackVerifier(SECRET, journal=OwnerReplayJournal(self.root))
        with self.assertRaisesRegex(SignedPlaybackError, "DURABLE_REPLAY"):
            two.verify(selection(), now_ms=TIME)
        # Check no replay poisoning from the rejected packet.
        valid = selection(nonce=NONCE_2, sent_at_ms=TIME+100)
        self.assertEqual(two.verify(valid, now_ms=TIME+100).nonce, NONCE_2)
        three = SignedPlaybackVerifier(SECRET, journal=OwnerReplayJournal(self.root))
        with self.assertRaisesRegex(SignedPlaybackError, "DURABLE_REPLAY"):
            three.verify(selection(nonce="1"*32, sent_at_ms=TIME-2000),
                         now_ms=TIME)

    def test_signed_state_boot_rotation_retires_old_boot_across_restarts(self):
        a = SignedRedmiStateCache(SECRET, journal=OwnerReplayJournal(self.root))
        a.receive(state(), now_ms=TIME, monotonic_s=10)
        b = SignedRedmiStateCache(SECRET, journal=OwnerReplayJournal(self.root))
        with self.assertRaisesRegex(RedmiStateRejected, "DURABLE_REPLAY"):
            b.receive(state(boot_id=BOOT_B, nonce="1"*32, sent_at_ms=TIME+4000),
                      now_ms=TIME+4000, monotonic_s=15)
        self.assertEqual(b.receive(
            state(boot_id=BOOT_B, nonce="2"*32, sent_at_ms=TIME+9000),
            now_ms=TIME+9000, monotonic_s=20).boot_id, BOOT_B)
        c = SignedRedmiStateCache(SECRET, journal=OwnerReplayJournal(self.root))
        # Rollback to retired boot A is forbidden even if A can produce a
        # valid signed higher-sequence packet within its timestamp window.
        with self.assertRaisesRegex(RedmiStateRejected, "DURABLE_REPLAY"):
            c.receive(state(boot_id=BOOT_A, sequence=3, nonce="3"*32,
                            sent_at_ms=TIME+9001),
                      now_ms=TIME+9001, monotonic_s=21)

    def test_tampered_or_wrong_key_state_cannot_poison_ledger(self):
        a = SignedRedmiStateCache(SECRET, journal=OwnerReplayJournal(self.root))
        tampered = json.loads(state())
        tampered["sequence"] = 100
        with self.assertRaisesRegex(RedmiStateRejected, "AUTH_FAILED"):
            a.receive(json.dumps(tampered).encode(), now_ms=TIME, monotonic_s=1)
        self.assertFalse(self.root.exists())
        a.receive(state(), now_ms=TIME, monotonic_s=2)
        self.assertTrue(self.root.exists())

    def test_corrupt_or_unavailable_journal_is_fail_closed(self):
        path = self.root / "p3-replay"
        path.mkdir(parents=True)
        (path / "ledger.sqlite3").write_bytes(b"not a sqlite3 database")
        cache = SignedRedmiStateCache(SECRET, journal=OwnerReplayJournal(self.root))
        with self.assertRaisesRegex(RedmiStateRejected, "DURABLE_REPLAY"):
            cache.receive(state(), now_ms=TIME, monotonic_s=5)
        with self.assertRaisesRegex(RedmiStateRejected, "STALE_OR_MISSING"):
            cache.read_fresh(monotonic_s=6)

    def test_sqlite_atomicity_under_two_concurrent_handlers(self):
        def try_accept(_):
            j = OwnerReplayJournal(self.root)
            try:
                j.accept_state(boot_id=BOOT_A, sequence=1,
                               nonce=NONCE_1, now_ms=TIME)
                return "ok"
            except ReplayJournalRejected:
                return "reject"
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(try_accept, [1,2]))
        self.assertCountEqual(results, ["ok", "reject"])
        with sqlite3.connect(self.root / "p3-replay" / "ledger.sqlite3") as c:
            self.assertEqual(c.execute(
                "SELECT COUNT(*) FROM recent_nonce "
                "WHERE stream='state'").fetchone()[0], 1)

    def test_durable_db_contains_no_media_hash_name_secret_or_server_profile(self):
        j = OwnerReplayJournal(self.root)
        j.accept_state(boot_id=BOOT_A, sequence=1,
                       nonce=NONCE_1, now_ms=TIME)
        j.accept_selection(nonce=NONCE_2, sent_ms=TIME, now_ms=TIME)
        with sqlite3.connect(self.root / "p3-replay" / "ledger.sqlite3") as c:
            rows = c.execute(
                "SELECT name FROM sqlite_master WHERE type='table'").fetchall()
            self.assertCountEqual([x[0] for x in rows],
                ["state_head", "retired_boots", "selection_head", "recent_nonce"])
            fields = []
            for table, in rows:
                fields.extend(x[1] for x in c.execute(
                    "PRAGMA table_info(" + table + ")").fetchall())
            self.assertNotIn("torrent_hash", fields)
            self.assertNotIn("filename", fields)
            self.assertNotIn("secret", fields)
            self.assertNotIn("url", fields)

    def test_real_owner_composition_always_installs_durable_verifiers(self):
        root = self.root / "media"
        root.mkdir(parents=True)
        reader = OwnerTorrServerReader(
            OwnerLocalTorrServer("owner-profile", 8090),
            transport=lambda *_: b'{}')
        wiring = compose_owner_redmi_status(
            p4_gateway=PairedActivation(device_secret=SECRET, supplied={}),
            paired_device_secret=SECRET, torrserver_reader=reader,
            owner_root=self.root, private_media_root=root,
            owner_auto_allowed=lambda:False,
            media_rights_allowed=lambda *_:False,
            verified_local_vi_state=lambda *_:"UNKNOWN",
            locate_owner_pinned_files=lambda *_:None)
        self.assertIsInstance(wiring.cache._journal, OwnerReplayJournal)
        self.assertIsInstance(wiring.signal._verifier._journal, OwnerReplayJournal)
        # No persisted ACTIVE state, no queue, and no LAN socket on compose.
        self.assertFalse((self.root / "inbox").exists())
        self.assertFalse((self.root / "p3-replay" / "ledger.sqlite3").exists())


if __name__ == "__main__":
    unittest.main()
