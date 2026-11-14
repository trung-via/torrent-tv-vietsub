"""Synthetic P3-TRIGGER gate tests: no network, provider, phone, PC or TV."""
import unittest

from activation_gate import PlaybackSelected, evaluate_playback, ActivationDeduplicator


def event(**overrides):
    values = dict(
        kind="PLAY_REQUEST_ACCEPTED",
        attested=True,
        active=True,
        server_id="owner-windows-server",
        tv_session_id="tv-session-1",
        torrent_hash="a" * 40,
        file_index=0,
        video_name="Example.Movie.2025.1080p.BluRay.x265-GROUP.mkv",
        owner_auto_enabled=True,
        subtitle_choice="ON",
        media_rights_approved=True,
        local_vi_state="ABSENT",
    )
    values.update(overrides)
    return PlaybackSelected(**values)


class TriggerGateTests(unittest.TestCase):
    def test_new_selected_video_dispatches_once(self):
        gate = ActivationDeduplicator()
        first = gate.consider(event())
        self.assertEqual((first.status, first.reason),
                         ("DISPATCH", "SEARCH_VI_FAST_THEN_EN"))
        self.assertRegex(first.local_fingerprint or "", r"^[0-9a-f]{64}$")
        self.assertEqual(gate.consider(event()).reason,
                         "DUPLICATE_CURRENT_PLAY_EVENT")

    def test_browsing_and_torrent_add_do_not_start_translation(self):
        for kind in ("TORRENT_ADDED", "CATALOG_OPENED", "SEARCH",
                     "PAUSE", "RESUME", "SEEK", "PLAYBACK_TICK",
                     "G2_REFRESH", "P4_REVISION_RECEIVED"):
            with self.subTest(kind=kind):
                self.assertEqual(evaluate_playback(event(kind=kind)).status, "SKIP")

    def test_phone_initiated_play_reaches_same_tv_play_request(self):
        # A trusted TV event is the canonical source; upstream phone need not
        # be modified or given Gemini/OpenSubtitles secrets.
        self.assertEqual(evaluate_playback(
            event(kind="PLAY_REQUEST_ACCEPTED")).status, "DISPATCH")

    def test_next_episode_is_new_selected_file(self):
        gate = ActivationDeduplicator()
        a = gate.consider(event())
        b = gate.consider(event(kind="NEXT_QUEUE_ITEM_ACCEPTED", file_index=1))
        a_again = gate.consider(event(kind="NEXT_QUEUE_ITEM_ACCEPTED", file_index=0))
        self.assertEqual((a.status, b.status, a_again.status),
                         ("DISPATCH", "DISPATCH", "DISPATCH"))
        self.assertNotEqual(a.local_fingerprint, b.local_fingerprint)
        self.assertEqual(a.local_fingerprint, a_again.local_fingerprint)

    def test_a_b_with_existing_vi_a_again_reactivates_without_reusing_b(self):
        gate = ActivationDeduplicator()
        self.assertEqual(gate.consider(event()).status, "DISPATCH")
        self.assertEqual(gate.consider(
            event(file_index=1, local_vi_state="PRESENT")).reason,
            "REUSE_EXISTING_VI")
        self.assertEqual(gate.consider(event()).status, "DISPATCH")

    def test_unknown_next_episode_then_return_to_original_can_dispatch(self):
        gate = ActivationDeduplicator()
        self.assertEqual(gate.consider(event()).status, "DISPATCH")
        self.assertEqual(gate.consider(
            event(file_index=1, local_vi_state="UNKNOWN")).status, "WAIT")
        self.assertEqual(gate.consider(event()).status, "DISPATCH")

    def test_off_and_other_never_authorize_provider(self):
        for choice in ("OFF", "OTHER"):
            with self.subTest(choice=choice):
                out = evaluate_playback(event(subtitle_choice=choice))
                self.assertEqual((out.status, out.reason),
                                 ("SKIP", "VIEWER_OFF_OR_OTHER"))

    def test_owner_opt_in_is_required(self):
        self.assertEqual(evaluate_playback(
            event(owner_auto_enabled=False)).reason, "OWNER_AUTO_DISABLED")

    def test_local_vi_is_reused_before_online_search(self):
        self.assertEqual(evaluate_playback(
            event(local_vi_state="PRESENT")).reason, "REUSE_EXISTING_VI")
        self.assertEqual(evaluate_playback(
            event(local_vi_state="UNKNOWN")).status, "WAIT")

    def test_unattested_or_stale_tv_session_holds(self):
        for delta in ({"attested": False}, {"active": False},
                      {"tv_session_id": ""}, {"server_id": ""}):
            with self.subTest(delta=delta):
                self.assertEqual(evaluate_playback(event(**delta)).status, "HOLD")

    def test_unauthorized_media_holds(self):
        self.assertEqual(evaluate_playback(
            event(media_rights_approved=False)).reason,
            "MEDIA_POLICY_NOT_APPROVED")

    def test_invalid_identity_and_path_are_rejected(self):
        for delta in ({"torrent_hash": "NOT_A_HASH"},
                      {"file_index": -1}, {"file_index": True},
                      {"video_name": "../unsafe.mkv"}, {"video_name": ""},
                      {"video_name": "a" * 256},
                      {"video_name": "X\\secret.mkv"},
                      {"subtitle_choice": "UNSET"},
                      {"local_vi_state": "WEAK"}):
            with self.subTest(delta=delta):
                self.assertEqual(evaluate_playback(event(**delta)).status, "HOLD")

    def test_filename_only_cannot_be_provider_identity(self):
        first = evaluate_playback(event())
        changed_torrent = evaluate_playback(event(torrent_hash="b" * 40))
        changed_server = evaluate_playback(event(server_id="other-server"))
        self.assertNotEqual(first.local_fingerprint, changed_torrent.local_fingerprint)
        self.assertNotEqual(first.local_fingerprint, changed_server.local_fingerprint)

    def test_restarting_deduplicator_does_not_fake_provider_idempotence(self):
        self.assertEqual(ActivationDeduplicator().consider(event()).status, "DISPATCH")
        self.assertEqual(ActivationDeduplicator().consider(event()).status, "DISPATCH")
        # Full persistent no-repeat GET/POST/Gemini behavior is #140's duty.

    def test_closed_session_resets_volatile_duplicate_guard(self):
        gate = ActivationDeduplicator()
        gate.consider(event())
        gate.on_session_closed()
        self.assertEqual(gate.consider(event()).status, "DISPATCH")


if __name__ == "__main__":
    unittest.main()
