"""Owner-private durable anti-replay for P3 status and selection envelopes.

Only boot ids, counters, nonces, receipt timestamps and a selection timestamp
are stored. NO TV/media identifiers, filename, subtitle data, IP, secrets or
API keys are ever written. SQLite BEGIN IMMEDIATE serializes concurrent HTTPS
handlers; synchronous=FULL and unique keys survive agent restart.

No port, service, Task Scheduler, remote API or provider code in this module.
Any corrupt/unavailable/unsafe journal raises and the caller MUST HOLD.
"""
from __future__ import annotations

from pathlib import Path
import os
import re
import sqlite3

_HEX32 = re.compile(r"[a-f0-9]{32}\Z")
_STREAM = frozenset(("state", "selection"))
_MAX_NONCES = 512
_NONCE_RETENTION_MS = 45_000
_MAX_RETIRED_BOOTS = 2048


class ReplayJournalRejected(ValueError):
    """Sanitized fail-closed reason; never include a file path."""


class OwnerReplayJournal:
    """Single-device owner-approved private ledger; NOT a session-state cache.

    A fresh signed state MUST still arrive after process restart. Persisted
    high-water marks prevent old signed packets from being accepted as fresh.
    """

    def __init__(self, owner_private_root: Path):
        if (not isinstance(owner_private_root, Path)
                or not owner_private_root.is_absolute()
                or owner_private_root.is_symlink()
                or owner_private_root.exists() and not owner_private_root.is_dir()):
            raise ReplayJournalRejected("P3_REPLAY_PRIVATE_ROOT_REQUIRED")
        self._dir = owner_private_root / "p3-replay"
        self._db = self._dir / "ledger.sqlite3"

    def _connect(self) -> sqlite3.Connection:
        try:
            if self._dir.is_symlink() or self._db.is_symlink():
                raise ReplayJournalRejected("P3_REPLAY_UNSAFE_JOURNAL")
            self._dir.mkdir(parents=True, mode=0o700, exist_ok=True)
            if self._dir.is_symlink() or self._db.is_symlink():
                raise ReplayJournalRejected("P3_REPLAY_UNSAFE_JOURNAL")
            # No URI filename, no shared-cache and no WAL sidecars.
            c = sqlite3.connect(str(self._db), timeout=3.0, isolation_level=None)
            try:
                c.execute("PRAGMA journal_mode=DELETE")
                c.execute("PRAGMA synchronous=FULL")
                c.execute("PRAGMA busy_timeout=3000")
                c.execute("CREATE TABLE IF NOT EXISTS state_head ("
                          "singleton INTEGER PRIMARY KEY CHECK(singleton=1), "
                          "boot TEXT NOT NULL, seq INTEGER NOT NULL, "
                          "received_ms INTEGER NOT NULL)")
                c.execute("CREATE TABLE IF NOT EXISTS retired_boots ("
                          "boot TEXT PRIMARY KEY)")
                c.execute("CREATE TABLE IF NOT EXISTS selection_head ("
                          "singleton INTEGER PRIMARY KEY CHECK(singleton=1), "
                          "sent_ms INTEGER NOT NULL)")
                c.execute("CREATE TABLE IF NOT EXISTS recent_nonce ("
                          "stream TEXT NOT NULL, nonce TEXT NOT NULL, "
                          "received_ms INTEGER NOT NULL, "
                          "PRIMARY KEY(stream,nonce))")
                if os.name != "nt":
                    os.chmod(self._dir, 0o700)
                    os.chmod(self._db, 0o600)
                return c
            except BaseException:
                c.close()
                raise
        except (OSError, sqlite3.Error, ReplayJournalRejected):
            raise ReplayJournalRejected("P3_REPLAY_JOURNAL_UNAVAILABLE") from None

    @staticmethod
    def _clock(now_ms: int, nonce: str) -> None:
        if (type(now_ms) is not int or now_ms < 1
                or type(nonce) is not str
                or _HEX32.fullmatch(nonce) is None):
            raise ReplayJournalRejected("P3_REPLAY_INPUT_INVALID")

    @staticmethod
    def _prune(c: sqlite3.Connection, stream: str, now_ms: int) -> None:
        c.execute("DELETE FROM recent_nonce WHERE stream=? AND received_ms<?",
                  (stream, now_ms - _NONCE_RETENTION_MS))
        count, = c.execute(
            "SELECT COUNT(*) FROM recent_nonce WHERE stream=?", (stream,)
        ).fetchone()
        if count >= _MAX_NONCES:
            raise ReplayJournalRejected("P3_REPLAY_JOURNAL_FULL")

    def accept_state(self, *, boot_id: str, sequence: int,
                     nonce: str, now_ms: int, ttl_ms: int = 8000) -> None:
        """Commit state nonce + sequence atomically, before publishing status."""
        self._clock(now_ms, nonce)
        if (type(boot_id) is not str or _HEX32.fullmatch(boot_id) is None
                or type(sequence) is not int or not 1 <= sequence < 2**63
                or type(ttl_ms) is not int or not 1000 <= ttl_ms <= 8000):
            raise ReplayJournalRejected("P3_REPLAY_STATE_INVALID")
        c = self._connect()
        try:
            c.execute("BEGIN IMMEDIATE")
            self._prune(c, "state", now_ms)
            if c.execute("SELECT 1 FROM recent_nonce WHERE stream='state' AND nonce=?",
                         (nonce,)).fetchone():
                raise ReplayJournalRejected("P3_REPLAY_STATE_NONCE")
            prior = c.execute(
                "SELECT boot,seq,received_ms FROM state_head WHERE singleton=1"
            ).fetchone()
            if prior is not None:
                boot, seq, last_ms = prior
                if boot == boot_id:
                    if sequence <= seq:
                        raise ReplayJournalRejected("P3_REPLAY_STATE_SEQUENCE")
                else:
                    if (now_ms <= last_ms
                            or now_ms - last_ms <= ttl_ms):
                        raise ReplayJournalRejected("P3_REPLAY_BOOT_STILL_FRESH")
                    if c.execute("SELECT 1 FROM retired_boots WHERE boot=?",
                                 (boot_id,)).fetchone():
                        raise ReplayJournalRejected("P3_REPLAY_RETIRED_BOOT")
                    retired_count, = c.execute(
                        "SELECT COUNT(*) FROM retired_boots").fetchone()
                    if retired_count >= _MAX_RETIRED_BOOTS:
                        raise ReplayJournalRejected("P3_REPLAY_BOOT_LEDGER_FULL")
                    c.execute("INSERT INTO retired_boots(boot) VALUES(?)", (boot,))
            # For the same boot a clock rollback must not reduce last_seen.
            timestamp = max(prior[2], now_ms) if prior is not None and prior[0] == boot_id else now_ms
            c.execute("INSERT INTO state_head(singleton,boot,seq,received_ms) "
                      "VALUES(1,?,?,?) ON CONFLICT(singleton) DO UPDATE SET "
                      "boot=excluded.boot,seq=excluded.seq,received_ms=excluded.received_ms",
                      (boot_id, sequence, timestamp))
            c.execute("INSERT INTO recent_nonce(stream,nonce,received_ms) "
                      "VALUES('state',?,?)", (nonce, now_ms))
            c.execute("COMMIT")
        except (sqlite3.Error, OSError, ReplayJournalRejected):
            try: c.execute("ROLLBACK")
            except sqlite3.Error: pass
            raise ReplayJournalRejected("P3_REPLAY_STATE_REJECTED") from None
        finally:
            c.close()

    def accept_selection(self, *, nonce: str, sent_ms: int, now_ms: int) -> None:
        """Deduplicate P3 Play/Next/Close across owner process restarts."""
        self._clock(now_ms, nonce)
        if type(sent_ms) is not int or sent_ms < 1:
            raise ReplayJournalRejected("P3_REPLAY_SELECTION_INVALID")
        c = self._connect()
        try:
            c.execute("BEGIN IMMEDIATE")
            self._prune(c, "selection", now_ms)
            if c.execute("SELECT 1 FROM recent_nonce WHERE stream='selection' AND nonce=?",
                         (nonce,)).fetchone():
                raise ReplayJournalRejected("P3_REPLAY_SELECTION_NONCE")
            prior = c.execute(
                "SELECT sent_ms FROM selection_head WHERE singleton=1").fetchone()
            if prior is not None and sent_ms + 1000 < prior[0]:
                raise ReplayJournalRejected("P3_REPLAY_SELECTION_OUT_OF_ORDER")
            next_sent = max(sent_ms, prior[0]) if prior else sent_ms
            c.execute("INSERT INTO selection_head(singleton,sent_ms) VALUES(1,?) "
                      "ON CONFLICT(singleton) DO UPDATE SET sent_ms=excluded.sent_ms",
                      (next_sent,))
            c.execute("INSERT INTO recent_nonce(stream,nonce,received_ms) "
                      "VALUES('selection',?,?)", (nonce, now_ms))
            c.execute("COMMIT")
        except (sqlite3.Error, OSError, ReplayJournalRejected):
            try: c.execute("ROLLBACK")
            except sqlite3.Error: pass
            raise ReplayJournalRejected("P3_REPLAY_SELECTION_REJECTED") from None
        finally:
            c.close()
