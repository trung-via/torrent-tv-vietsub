"""Verify G1 native mediaKey matches Python V3 mapping (synthetic)."""
from __future__ import annotations

from pathlib import Path
import unittest

from matcher import Media
from owner_selected_file_resolver import _fingerprint
from p3_p4_media_key import P4MediaKeyError, p4_media_key


PROFILE = "owner-main-laptop-torrserver"
HASH = "a"*40
FILE = "Synthetic.Movie.2017.1080p.BluRay.x265-GRP.mkv"


class P4MediaIdentityTests(unittest.TestCase):
    def test_fixed_p4_key_vector_matches_g1_kotlin_canonical_format(self):
        key = p4_media_key(Media(PROFILE,HASH,3,FILE),vlc_selected=True)
        self.assertEqual(
            key,
            "media.8fc8dce36e2438ea7628f72c8ef587d11402003af3c692cf7c2cb92758087928")
        root = Path(__file__).resolve().parent.parent / "g1-prod"
        source = (root / "P1ProductionSubtitles.kt").read_text("utf-8")
        self.assertIn('return "media." + sha(("prod\\u0000"', source)
        self.assertIn("hash.lowercase(Locale.ROOT)", source)

    def test_p3_source_fingerprint_is_not_native_p4_key(self):
        media=Media(PROFILE,HASH,3,FILE)
        fp=_fingerprint(PROFILE,HASH,3)
        p4=p4_media_key(media,vlc_selected=True)
        self.assertNotEqual(fp,p4.removeprefix("media."))
        self.assertEqual(len(fp),64)
        self.assertEqual(len(p4),70)

    def test_same_movie_filename_different_episode_server_or_torrent_is_distinct(self):
        keys=[]
        for media in (
            Media(PROFILE,HASH,3,FILE),
            Media(PROFILE,HASH,4,FILE),
            Media("different-profile",HASH,3,FILE),
            Media(PROFILE,"b"*40,3,FILE),
        ):
            keys.append(p4_media_key(media,vlc_selected=True))
        self.assertEqual(len(set(keys)),len(keys))

    def test_p4_40_hex_vlc_profile_gate_is_stricter_than_v3(self):
        bads=[
            Media(PROFILE,HASH,3,FILE),
        ]
        with self.assertRaisesRegex(P4MediaKeyError,"IDENTITY_NOT_READY"):
            p4_media_key(bads[0],vlc_selected=False)
        for media in (
            Media(PROFILE,"a"*64,3,FILE),
            Media("bad profile",HASH,3,FILE),
            Media(PROFILE,HASH,-1,FILE),
            Media(PROFILE,HASH,True,FILE),
        ):
            with self.subTest(media=media):
                with self.assertRaisesRegex(P4MediaKeyError,"IDENTITY_NOT_READY"):
                    p4_media_key(media,vlc_selected=True)


if __name__=="__main__":
    unittest.main()
