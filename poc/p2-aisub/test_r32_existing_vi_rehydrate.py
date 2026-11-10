"""Synthetic-only private SRT/VI recovery, no network/provider/user film."""
from __future__ import annotations

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from cue_pipeline import Cue, render
from r32_existing_vi_rehydrate import (
    BATCH_SIZE, CONFIRM, SCHEMA, RecoveryError,
    create_new_v1_cache, plan_existing_vi, verify_new_v1_cache, main,
)


def pair(count=3, fmt="srt"):
    en = tuple(Cue(i, 1000 * i, 1000 * i + 900, "Hello world.") for i in range(1, count + 1))
    vi = tuple(Cue(i, 1000 * i, 1000 * i + 900, "Xin chào bạn.") for i in range(1, count + 1))
    return render(en, fmt), render(vi, fmt)


class RecoveryV1Tests(unittest.TestCase):
    def test_readonly_plan_three_cues(self):
        en, vi = pair()
        report = plan_existing_vi(en, vi, "srt")
        self.assertEqual(report["cue_count"], 3)
        self.assertEqual(report["batch_count"], 1)
        self.assertEqual(report["provider_calls"], 0)
        self.assertEqual(report["semantic_review"], "NOT_PERFORMED")

    def test_full_1761_split_20_and_no_model(self):
        en, vi = pair(1761)
        report = plan_existing_vi(en, vi, "srt")
        self.assertEqual(report["cue_count"], 1761)
        self.assertEqual(report["batch_count"], 20)
        self.assertEqual(report["batch_size"], 90)

    def test_mismatched_timing_is_rejected(self):
        en, vi = pair()
        vi = vi.replace(b"00:00:02,000", b"00:00:02,020", 1)
        with self.assertRaisesRegex(RecoveryError, "RECOVERY_CUE_TIME_OR_ID_MISMATCH"):
            plan_existing_vi(en, vi, "srt")

    def test_missing_cue_rejected(self):
        en, _ = pair(4)
        _, vi = pair(3)
        with self.assertRaisesRegex(RecoveryError, "RECOVERY_CUE_COUNT_MISMATCH"):
            plan_existing_vi(en, vi, "srt")

    def test_broken_utf8_rejected(self):
        en, _ = pair()
        with self.assertRaisesRegex(RecoveryError, "RECOVERY_INVALID_SRT_VTT"):
            plan_existing_vi(en, b"\xff", "srt")

    def test_plain_markup_rejected(self):
        en, vi = pair()
        vi = vi.replace("Xin chào bạn.".encode(), b"<script>alert(1)</script>")
        with self.assertRaisesRegex(RecoveryError, "RECOVERY_UNSAFE_VI_TEXT"):
            plan_existing_vi(en, vi, "srt")

    def test_vtt_with_ids_and_time_parity(self):
        en, vi = pair(3, "vtt")
        report = plan_existing_vi(en, vi, "vtt")
        self.assertEqual(report["timecode_parity"], "PASS")

    def test_all_english_identical_cues_are_not_called_translated(self):
        en, _ = pair()
        with self.assertRaisesRegex(RecoveryError, "RECOVERY_ALL_CUES_IDENTICAL_TO_SOURCE"):
            plan_existing_vi(en, en, "srt")

    def test_cannot_write_without_confirmation(self):
        en, vi = pair()
        with tempfile.TemporaryDirectory() as d:
            src, tr = Path(d)/"en.srt", Path(d)/"vi.srt"
            src.write_bytes(en); tr.write_bytes(vi)
            with self.assertRaisesRegex(RecoveryError, "RECOVERY_EXPLICIT_CONFIRMATION_REQUIRED"):
                create_new_v1_cache(src, tr, Path(d)/"new", fmt="srt", confirm="")
            self.assertFalse((Path(d)/"new").exists())

    def test_new_private_cache_and_readback_with_1761_cues(self):
        en, vi = pair(1761)
        with tempfile.TemporaryDirectory() as d:
            src, tr, dest = Path(d)/"en.srt", Path(d)/"vi.srt", Path(d)/"fresh"
            src.write_bytes(en); tr.write_bytes(vi)
            out = create_new_v1_cache(src, tr, dest, fmt="srt", confirm=CONFIRM)
            self.assertEqual(out["status"], "NEW_PRIVATE_CACHE_VERIFIED_NO_PROVIDER")
            self.assertEqual(out["batch_count"], 20)
            self.assertEqual(len(list((dest/"work").glob("batch_*.json"))), 20)
            last = json.loads((dest/"work"/"batch_020.json").read_text())
            self.assertEqual((last["first_cue_id"],last["last_cue_id"]),(1711,1761))
            self.assertEqual(json.loads((dest/"work"/"input_manifest.json").read_text())["schema"], SCHEMA)
            self.assertEqual(verify_new_v1_cache(en, dest, fmt="srt")["status"],
                             "VERIFIED_NEW_V1_CACHE_ALL_CACHED_NO_PROVIDER")
            self.assertEqual(src.read_bytes(),en)
            self.assertEqual(tr.read_bytes(),vi)

    def test_existing_dest_rejected_without_overwrite(self):
        en, vi = pair()
        with tempfile.TemporaryDirectory() as d:
            src, tr, dest = Path(d)/"en.srt", Path(d)/"vi.srt", Path(d)/"old"
            src.write_bytes(en); tr.write_bytes(vi)
            dest.mkdir()
            marker = dest/"old-data.txt"; marker.write_text("PRESERVE",encoding="utf8")
            with self.assertRaisesRegex(RecoveryError,"RECOVERY_OUTPUT_ALREADY_EXISTS"):
                create_new_v1_cache(src,tr,dest,fmt="srt",confirm=CONFIRM)
            self.assertEqual(marker.read_text(),"PRESERVE")

    def test_refuses_new_output_nested_under_legacy_workdir(self):
        en,vi=pair()
        with tempfile.TemporaryDirectory() as d:
            src,tr=Path(d)/"en.srt",Path(d)/"vi.srt"
            src.write_bytes(en);tr.write_bytes(vi)
            old_work=Path(d)/"work";old_work.mkdir()
            (old_work/"input_manifest.json").write_text('{}',encoding='utf8')
            with self.assertRaisesRegex(RecoveryError,"RECOVERY_OUTPUT_PARENT_IS_EXISTING_WORKDIR"):
                create_new_v1_cache(src,tr,old_work/"new-cache",fmt="srt",confirm=CONFIRM)
            self.assertFalse((old_work/"new-cache").exists())

    def test_vtt_cache_creation_readback(self):
        en,vi=pair(101,fmt="vtt")
        with tempfile.TemporaryDirectory() as d:
            src,tr,dest=Path(d)/"en.vtt",Path(d)/"vi.vtt",Path(d)/"new-cache"
            src.write_bytes(en);tr.write_bytes(vi)
            result=create_new_v1_cache(src,tr,dest,fmt="vtt",confirm=CONFIRM)
            self.assertEqual(result["batch_count"],2)
            self.assertEqual(verify_new_v1_cache(en,dest,fmt="vtt")["cue_count"],101)

    def test_unknown_legacy_manifest_blocked(self):
        en, _ = pair()
        with tempfile.TemporaryDirectory() as d:
            work = Path(d)/"work";work.mkdir()
            (work/"input_manifest.json").write_text('{"batch_size":90}',encoding="utf8")
            with self.assertRaisesRegex(RecoveryError,"RECOVERY_LEGACY_OR_UNKNOWN_SCHEMA_NO_AUTOMIGRATION"):
                verify_new_v1_cache(en,Path(d),fmt="srt")

    def test_tamper_checkpoint_bytes_detected(self):
        en, vi = pair()
        with tempfile.TemporaryDirectory() as d:
            src, tr, dest=Path(d)/"a.srt",Path(d)/"b.srt",Path(d)/"cache"
            src.write_bytes(en);tr.write_bytes(vi)
            create_new_v1_cache(src,tr,dest,fmt="srt",confirm=CONFIRM)
            p=dest/"work"/"batch_001.json"
            p.write_bytes(p.read_bytes().replace("Xin chào".encode(),"Xuyên tạc".encode()))
            with self.assertRaisesRegex(RecoveryError,"RECOVERY_CHECKPOINT_HASH_MISMATCH"):
                verify_new_v1_cache(en,dest,fmt="srt")

    def test_extra_checkpoint_refused(self):
        en, vi = pair()
        with tempfile.TemporaryDirectory() as d:
            src, tr, dest=Path(d)/"a.srt",Path(d)/"b.srt",Path(d)/"fresh"
            src.write_bytes(en);tr.write_bytes(vi)
            create_new_v1_cache(src,tr,dest,fmt="srt",confirm=CONFIRM)
            (dest/"work"/"batch_999.json").write_text('{}', encoding='utf8')
            with self.assertRaisesRegex(RecoveryError,"RECOVERY_EXTRA_OR_MISSING_CHECKPOINT"):
                verify_new_v1_cache(en,dest,fmt="srt")

    def test_different_source_detected(self):
        en, vi=pair()
        with tempfile.TemporaryDirectory() as d:
            src, tr, dest=Path(d)/"a.srt",Path(d)/"b.srt",Path(d)/"fresh"
            src.write_bytes(en);tr.write_bytes(vi)
            create_new_v1_cache(src,tr,dest,fmt="srt",confirm=CONFIRM)
            tampered=en.replace(b"Hello world.",b"Different dialogue.",1)
            with self.assertRaisesRegex(RecoveryError,"RECOVERY_MANIFEST_IDENTITY_MISMATCH"):
                verify_new_v1_cache(tampered,dest,fmt="srt")

    def test_partial_deleted_checkpoint_blocked(self):
        en,vi=pair(105)
        with tempfile.TemporaryDirectory() as d:
            src,tr,dest=Path(d)/"a.srt",Path(d)/"b.srt",Path(d)/"fresh"
            src.write_bytes(en);tr.write_bytes(vi)
            create_new_v1_cache(src,tr,dest,fmt="srt",confirm=CONFIRM)
            (dest/"work"/"batch_002.json").unlink()
            with self.assertRaisesRegex(RecoveryError,"RECOVERY_EXTRA_OR_MISSING_CHECKPOINT"):
                verify_new_v1_cache(en,dest,fmt="srt")

    def test_cli_private_text_and_paths_never_printed(self):
        en,vi=pair()
        with tempfile.TemporaryDirectory() as d:
            src,tr=Path(d)/"PRIVATE_EN.srt",Path(d)/"PRIVATE_VI.srt"
            src.write_bytes(en);tr.write_bytes(vi)
            out=io.StringIO()
            with patch.object(sys,"argv",["prog","--source",str(src),"--translated",str(tr)]):
                with redirect_stdout(out):
                    self.assertEqual(main(),0)
            s=out.getvalue()
            for word in (str(src),str(tr),"Xin chào","Hello world"):
                self.assertNotIn(word,s)
            self.assertEqual(json.loads(s)["status"],"EXISTING_VI_TIMING_PARITY_PASS_MEANING_UNVERIFIED")

    def test_cli_bad_file_only_code_not_path(self):
        with tempfile.TemporaryDirectory() as d:
            src,tr=Path(d)/"SECRET_EN.srt",Path(d)/"SECRET_VI.srt"
            src.write_bytes(b'bad');tr.write_bytes(b'bad')
            out=io.StringIO()
            with patch.object(sys,"argv",["prog","--source",str(src),"--translated",str(tr)]):
                with redirect_stdout(out):
                    self.assertEqual(main(),2)
            self.assertNotIn(str(src),out.getvalue())
            self.assertEqual(json.loads(out.getvalue())["status"],"BLOCKED")

if __name__=="__main__":unittest.main()
