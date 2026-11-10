"""Synthetic source-only R3.3 tests. No model, film or network calls."""
from __future__ import annotations
import json
import hashlib
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from cue_pipeline import Cue, parse_cues, render
from r33_new_film_core import (
    R33Blocked, SCHEMA, RUN_CONFIRM, BATCH_SIZE, MODEL_PIN,
    exclusive_owner, run_new_film, inspect_existing, main,
)


def sample(count=7, fmt="srt", *, text="English hello") -> bytes:
    cues = tuple(Cue(i, (i-1)*3000+1000, (i-1)*3000+2900, text)
                 for i in range(1, count+1))
    return render(cues, fmt)


class NewFilmCoreTests(unittest.TestCase):
    def _run(self, src, dirpath, *, fmt="srt", mode="normal", workers=3):
        seen, contexts = [], []
        def context(cues):
            contexts.append(len(cues))
            return "mock whole-story context"
        def provider(batch_id, cues, story_context):
            seen.append(batch_id)
            if mode=="quota" and batch_id==2:
                raise RuntimeError("PRIVATE_TOKEN_AND_RAW_SUBTITLE_DO_NOT_LOG")
            if mode=="bad" and batch_id==2:
                return {"wrong": "invalid"}
            if mode=="empty":
                return {str(c.number): "" for c in cues}
            return {str(c.number): "Xin chào" for c in cues}
        result = run_new_film(src, fmt, dirpath, confirm=RUN_CONFIRM,
                              full_story_context=context,translate_batch=provider,
                              max_workers=workers)
        return result, seen, contexts

    def test_1761_cues_20_batches_and_all_cached_second_run_no_provider(self):
        src=sample(1761)
        with TemporaryDirectory() as td:
            p=Path(td)/"r33_fresh"
            result,seen,context=self._run(src,p,workers=4)
            self.assertEqual(result["cue_count"],1761)
            self.assertEqual(result["batch_count"],20)
            self.assertEqual(sorted(seen),list(range(1,21)))
            self.assertEqual(context,[1761])
            self.assertEqual(len(list((p/"work").glob("batch_*.json"))),20)
            translated=(p/"translated.vi.srt").read_bytes()
            self.assertEqual(len(parse_cues(translated,"srt")),1761)
            self.assertEqual(result["vi_sha256"],hashlib.sha256(translated).hexdigest())
            output_before=hashlib.sha256(translated).hexdigest()
            def no_network(*args):raise AssertionError("provider should never run")
            resumed=run_new_film(src,"srt",p,confirm=RUN_CONFIRM,
                                 full_story_context=no_network,translate_batch=no_network)
            self.assertEqual(resumed["provider_batches"],0)
            self.assertEqual(resumed["cached_prior_batches"],20)
            self.assertEqual(hashlib.sha256((p/"translated.vi.srt").read_bytes()).hexdigest(),output_before)

    def test_no_confirmation_does_not_make_directory_or_call_provider(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            with self.assertRaisesRegex(R33Blocked,"R33_RUN_CONFIRMATION_REQUIRED"):
                run_new_film(sample(),"srt",p,confirm="",
                             full_story_context=lambda x:self.fail(),
                             translate_batch=lambda *x:self.fail())
            self.assertFalse(p.exists())

    def test_quota_stop_preserves_verified_checkpoint_then_resume(self):
        src=sample(182)
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            with self.assertRaises(R33Blocked) as e:
                self._run(src,p,mode="quota",workers=1)
            self.assertEqual(e.exception.code,"R33_R32_PROVIDER_FAILURE")
            self.assertNotIn("PRIVATE",str(e.exception))
            self.assertTrue((p/"work"/"batch_001.json").exists())
            self.assertFalse((p/"work"/"batch_002.json").exists())
            self.assertFalse((p/"translated.vi.srt").exists())
            original=(p/"work"/"batch_001.json").read_bytes()
            result,seen,context=self._run(src,p,workers=1)
            self.assertEqual(seen,[2,3])
            self.assertEqual(result["cached_prior_batches"],1)
            self.assertEqual(original,(p/"work"/"batch_001.json").read_bytes())

    def test_bad_provider_response_fail_closed(self):
        with TemporaryDirectory() as td:
            with self.assertRaisesRegex(R33Blocked,"R33_R32_INVALID_PROVIDER_RESULT"):
                self._run(sample(181),Path(td)/"new",mode="bad",workers=1)

    def test_empty_vi_fails_without_checkpoint(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            with self.assertRaisesRegex(R33Blocked,"R33_R32_INVALID_PROVIDER_RESULT"):
                self._run(sample(1),p,mode="empty",workers=1)
            self.assertFalse((p/"work"/"batch_001.json").exists())

    def test_source_mismatch_does_not_reuse_cache(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            self._run(sample(),p)
            with self.assertRaisesRegex(R33Blocked,"R33_MANIFEST_SOURCE_OR_MODEL_MISMATCH"):
                self._run(sample(text="Changed original"),p)

    def test_corrupted_cached_checkpoint_blocks_before_context_or_model(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            self._run(sample(91),p)
            with (p/"work"/"batch_001.json").open("ab") as f:f.write(b"\n corrupt\n")
            with self.assertRaises(R33Blocked):
                run_new_film(sample(91),"srt",p,confirm=RUN_CONFIRM,
                             full_story_context=lambda *a:self.fail("NO_CONTEXT"),
                             translate_batch=lambda *a:self.fail("NO_PROVIDER"))

    def test_checkpoint_id_tamper_rejected_even_if_valid_json(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            self._run(sample(2),p)
            cp=p/"work"/"batch_001.json"
            body=json.loads(cp.read_text(encoding="utf-8"))
            body["cues"][0]["id"]=100
            cp.write_text(json.dumps(body),encoding="utf-8")
            with self.assertRaisesRegex(R33Blocked,"R33_CHECKPOINT_HASH_INVALID"):
                self._run(sample(2),p)

    def test_valid_json_translation_tamper_detected_by_digest(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            self._run(sample(2),p)
            cp=p/"work"/"batch_001.json"
            record=json.loads(cp.read_text(encoding="utf-8"))
            record["cues"][0]["text"]="Thông tin bị sửa"
            cp.write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
            with self.assertRaisesRegex(R33Blocked,"R33_CHECKPOINT_HASH_INVALID"):
                self._run(sample(2),p)

    def test_legacy_workdir_rejected_and_unmodified(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"historical"
            p.mkdir()
            (p/"work").mkdir()
            old=(p/"work"/"input_manifest.json")
            old.write_bytes(b"{\"legacy\":true}")
            with self.assertRaises(R33Blocked):
                self._run(sample(),p)
            self.assertEqual(old.read_bytes(),b"{\"legacy\":true}")
            self.assertFalse((p/"work"/"r33_manifest.json").exists())

    def test_parent_legacy_workdir_refused(self):
        with TemporaryDirectory() as td:
            d=Path(td)/"previous"
            d.mkdir();(d/"work").mkdir();(d/"work"/"input_manifest.json").write_text("legacy")
            with self.assertRaisesRegex(R33Blocked,"R33_PARENT_IS_LEGACY_WORKDIR"):
                self._run(sample(),d/"r33_new")

    def test_output_hash_modified_causes_fail_closed_without_overwrite(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            self._run(sample(2),p)
            out=p/"translated.vi.srt"
            out.write_bytes(b"X")
            with self.assertRaisesRegex(R33Blocked,"R33_EXISTING_OUTPUT_HASH_MISMATCH"):
                self._run(sample(2),p)
            self.assertEqual(out.read_bytes(),b"X")

    def test_extra_batch_not_silently_ignored(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            self._run(sample(),p)
            (p/"work"/"batch_999.json").write_bytes(b"bad")
            with self.assertRaisesRegex(R33Blocked,"R33_UNKNOWN_BATCH_FILE_PRESENT"):
                self._run(sample(),p)

    def test_owner_lock_conflict_rejected_without_provider(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            self._run(sample(),p)
            with exclusive_owner(p/"work"/".r33_owner.lock"):
                with self.assertRaisesRegex(R33Blocked,"R33_WORKDIR_ALREADY_ACTIVE"):
                    self._run(sample(),p)

    def test_vtt_roundtrip_preserves_timing(self):
        with TemporaryDirectory() as td:
            src=sample(4,"vtt")
            p=Path(td)/"new"
            r,_,_=self._run(src,p,fmt="vtt")
            self.assertEqual(r["cue_count"],4)
            self.assertEqual([(x.start_ms,x.end_ms) for x in parse_cues(src,"vtt")],
                [(x.start_ms,x.end_ms) for x in parse_cues((p/"translated.vi.vtt").read_bytes(),"vtt")])

    def test_readonly_inspector_does_not_create_or_call_provider(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"not_created"
            self.assertEqual(inspect_existing(sample(),"srt",p)["status"],"R33_WORKDIR_NOT_CREATED")
            self.assertFalse(p.exists())
            self._run(sample(91),p)
            out=inspect_existing(sample(91),"srt",p)
            self.assertEqual(out["cached_batches_valid"],2)
            self.assertEqual(out["model_calls"],0)

    def test_manifest_must_match_exact_model_and_config(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            self._run(sample(),p)
            f=p/"work"/"r33_manifest.json"
            body=json.loads(f.read_text())
            body["model_pin"]="UNKNOWN_FAKE_MODEL"
            f.write_text(json.dumps(body))
            with self.assertRaisesRegex(R33Blocked,"R33_MANIFEST_SOURCE_OR_MODEL_MISMATCH"):
                self._run(sample(),p)

    def test_invalid_format_and_worker_preflight(self):
        with TemporaryDirectory() as td:
            p=Path(td)/"new"
            with self.assertRaisesRegex(R33Blocked,"R33_SOURCE_SIZE_OR_FORMAT_INVALID"):
                self._run(sample(),p,fmt="txt")
            self.assertFalse(p.exists())
            for workers in (0,5,True):
                with self.subTest(workers=workers),self.assertRaisesRegex(R33Blocked,"R33_INVALID_WORKER_COUNT"):
                    self._run(sample(),p,workers=workers)

    def test_readonly_cli_no_paths_or_subtitle_text(self):
        import io,sys
        from contextlib import redirect_stdout
        with TemporaryDirectory() as td:
            src=Path(td)/"private_film.en.srt";src.write_bytes(sample())
            dest=Path(td)/"not_created"
            buff=io.StringIO()
            with patch.object(sys,"argv",["inspect","--source",str(src),"--workdir",str(dest)]):
                with redirect_stdout(buff):self.assertEqual(main(),0)
            self.assertEqual(json.loads(buff.getvalue())["status"],"R33_WORKDIR_NOT_CREATED")
            self.assertNotIn(str(src),buff.getvalue())
            self.assertNotIn("English hello",buff.getvalue())

    def test_no_network_or_cli_provider_by_default(self):
        import inspect,r33_new_film_core as core
        src=inspect.getsource(core)
        for forbidden in ("import subprocess", "import requests", "import urllib", "import socket", "agy -p", "api_key"):
            self.assertNotIn(forbidden,src)

if __name__=="__main__":unittest.main()
