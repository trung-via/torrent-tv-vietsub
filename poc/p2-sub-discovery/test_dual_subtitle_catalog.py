"""No provider or Windows/Redmi effects. Synthetic two-source cache proofs."""
import hashlib
from pathlib import Path
import tempfile
import unittest

from dual_subtitle_catalog import DualSubtitleCatalog
from matcher import Media
from opensubtitles import Asset, SubtitleApiError, write_private_cache


def srt(text):
    return f"1\n00:00:01,000 --> 00:00:02,000\n{text}\n".encode()


def media(name="Film.A.2026.mkv", index=0):
    m = Media("server", "a" * 40, index, name)
    fp = hashlib.sha256(("\x00".join((
        m.server_profile_id, m.torrent_hash, str(m.file_index)))).encode()).hexdigest()
    return m, fp


def asset(lang, ident, text):
    payload = srt(text)
    return Asset(ident, lang, "srt", payload,
                 hashlib.sha256(payload).hexdigest(), 1)


class DualCatalogTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve() / "cache"
        self.catalog = DualSubtitleCatalog(self.root)
        self.a, self.fp = media()

    def save(self, kind, src, matched=False, *, m=None, fp=None):
        m = m or self.a
        fp = fp or self.fp
        return self.catalog.record(
            m, fp, kind, src, write_private_cache(self.root, m, src),
            release_matched=matched)

    def test_ai_and_unverified_vi_can_coexist_for_one_exact_film(self):
        en = asset("en", 5, "Original English")
        vi = asset("vi", 7, "Bản dịch Việt có sẵn")
        ai_receipt = self.save("ai_en", en)
        vi_receipt = self.save("downloaded_vi", vi)
        self.assertNotEqual(ai_receipt.file, vi_receipt.file)
        self.assertFalse(vi_receipt.release_matched)
        self.assertEqual(self.catalog.read(self.a, self.fp, "ai_en"), ai_receipt)
        self.assertEqual(self.catalog.read(self.a, self.fp, "downloaded_vi"), vi_receipt)
        self.assertEqual(self.save("ai_en", en), ai_receipt)
        self.assertEqual(self.save("downloaded_vi", vi), vi_receipt)
        self.assertFalse(list(self.root.glob(".auto-source-*.json")))

    def test_media_a_b_a_isolation_and_mismatched_fingerprint(self):
        self.save("downloaded_vi", asset("vi", 7, "A"))
        other, other_fp = media("Film.B.2026.mkv", 1)
        self.assertIsNone(self.catalog.read(other, other_fp, "downloaded_vi"))
        with self.assertRaisesRegex(SubtitleApiError, "DUAL_MEDIA_BINDING_MISMATCH"):
            self.catalog.read(other, self.fp, "downloaded_vi")
        self.save("downloaded_vi", asset("vi", 8, "B"), m=other, fp=other_fp)
        self.assertEqual(self.catalog.read(self.a, self.fp, "downloaded_vi").cues, 1)

    def test_tampered_file_or_index_is_not_reused(self):
        receipt = self.save("ai_en", asset("en", 5, "Good"))
        receipt.file.write_bytes(srt("Changed"))
        with self.assertRaisesRegex(SubtitleApiError, "DUAL_SOURCE_CONTENT_CHANGED"):
            self.catalog.read(self.a, self.fp, "ai_en")

    def test_index_collision_and_language_confusion_fail_closed(self):
        self.save("downloaded_vi", asset("vi", 7, "One"))
        with self.assertRaisesRegex(SubtitleApiError, "DUAL_SOURCE_INDEX_CONFLICT"):
            self.save("downloaded_vi", asset("vi", 8, "Two"))
        with self.assertRaisesRegex(SubtitleApiError, "DUAL_SOURCE_FILE_INVALID"):
            self.save("ai_en", asset("vi", 9, "Wrong"))
        with self.assertRaisesRegex(SubtitleApiError, "DUAL_SOURCE_KIND_INVALID"):
            self.catalog.read(self.a, self.fp, "arbitrary")


if __name__ == "__main__":
    unittest.main()
