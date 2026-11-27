"""Synthetic only. No provider, real torrent, network or TV."""
from dataclasses import replace
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock
from owner_movie_handoff import SelectedRelease, HandoffHold, add_selected_release

H = "a" * 40
S = SelectedRelease("magnet:?xt=urn:btih:" + H, H, "Licensed fixture",
                    True, True, True)
META = {"hash": H, "file_stats": [{"id": 7, "path": "fixture.mp4"},
                                  {"id": 8, "path": "sample.mp4"}]}

class HandoffTests(unittest.TestCase):
    def test_add_once_then_library_dedupe(self):
        with TemporaryDirectory() as d:
            p = Mock(side_effect=[[], [], {"hash": H}, [{"hash": H}], META,
                                  [{"hash": H}], META])
            root = Path(d)
            a = add_selected_release(S, root, post=p)
            b = add_selected_release(S, root, post=p)
            self.assertEqual((a.status, a.file_id, a.added_now), ("LIBRARY_READY", 7, True))
            self.assertFalse(b.added_now)
            self.assertEqual([c.args[0]["action"] for c in p.call_args_list].count("add"), 1)

    def test_uncertain_effect_not_replayed(self):
        with TemporaryDirectory() as d:
            root = Path(d)
            p = Mock(side_effect=[[], [], TimeoutError(), []])
            with self.assertRaisesRegex(HandoffHold, "TS_ADD_EFFECT_UNVERIFIED"):
                add_selected_release(S, root, post=p)
            with self.assertRaisesRegex(HandoffHold, "TS_PRIOR_ADD_REVIEW_REQUIRED"):
                add_selected_release(S, root, post=p)
            self.assertEqual([c.args[0]["action"] for c in p.call_args_list].count("add"), 1)

    def test_authority_and_identity_before_io(self):
        with TemporaryDirectory() as d:
            p = Mock()
            for s in (replace(S, media_authorized=False), replace(S, release_matched=False),
                      replace(S, expected_hash="b"*40)):
                with self.assertRaises(HandoffHold):
                    add_selected_release(s, Path(d), post=p)
            p.assert_not_called()

    def test_multiple_files_never_guess(self):
        with TemporaryDirectory() as d:
            m = {"hash": H, "file_stats": [{"id": 1, "path": "a.mkv"}, {"id": 2, "path": "b.mp4"}]}
            p = Mock(side_effect=[[{"hash": H}], m, [{"hash": H}], m])
            a = add_selected_release(S, Path(d), post=p)
            self.assertEqual(a.status, "FILE_SELECTION_PENDING")
            self.assertIsNone(a.file_id)
            b = add_selected_release(replace(S, file_id=2), Path(d), post=p)
            self.assertEqual(b.file_id, 2)
            self.assertFalse(b.added_now)

    def test_metadata_mismatch_does_not_return_playable(self):
        with TemporaryDirectory() as d:
            p = Mock(side_effect=[[{"hash": H}], {"hash": "b"*40}])
            with self.assertRaisesRegex(HandoffHold, "TS_METADATA_HASH_MISMATCH"):
                add_selected_release(S, Path(d), post=p)

if __name__ == "__main__":
    unittest.main()
