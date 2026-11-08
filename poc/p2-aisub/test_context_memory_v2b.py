"""Context Memory v2b: source/digest, temporal continuity and no-inference tests."""
from __future__ import annotations

from contextlib import redirect_stdout
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from context_memory_v2b import (
    CONFIRM, PLAN_SCHEMA, _stable_digest, create_memory_plan,
    inspect_memory, main,
)
from context_engine_v2 import _canonical_source_sha256
from cue_pipeline import parse_cues, render

ROOT = Path(__file__).with_name("fixtures")
SRT = ROOT / "agy_scene12_en.srt"
CONTEXT = ROOT / "context_v2_synthetic.json"
MEMORY = ROOT / "context_memory_v2b_synthetic.json"


def inputs():
    return (SRT.read_bytes(), json.loads(CONTEXT.read_text(encoding="utf-8")),
            json.loads(MEMORY.read_text(encoding="utf-8")))


def translation_map():
    return {str(i): "Đã đến." for i in range(1, 13)}


def plan_triplet():
    source, meta, journal = inputs()
    return create_memory_plan(source, "srt", meta, journal)


class ContextMemoryV2BTests(unittest.TestCase):

    def test_authored_pins_and_event_order_have_no_inferred_source(self):
        source, meta, journal = inputs()
        self.assertEqual(journal["source_sha256"], _canonical_source_sha256(source))
        self.assertEqual(journal["base_context_sha256"], _stable_digest(meta))
        self.assertEqual([x["scene_id"] for x in journal["events"]],
                         ["station_reunion", "station_decision"])
        self.assertEqual([x["evidence"] for x in journal["events"]],
                         ["fixture_authored", "fixture_authored"])

    def test_scene_one_alias_and_relation_remain_original(self):
        plan = plan_triplet()
        first = plan["scenes"][0]
        self.assertEqual(plan["schema"], PLAN_SCHEMA)
        self.assertEqual(plan["applied_events"], 2)
        self.assertEqual(plan["address_transitions"], 1)
        self.assertEqual(first["memory_state_at_scene_start"]["applied_event_ids"], ["m01-alias"])
        self.assertEqual(first["memory_state_at_scene_start"]["confirmed_aliases_untrusted"][0]["alias"], "Mây")
        first_cue = first["batches"][0]["target"][0]
        self.assertEqual(first_cue["address"]["self"], "em")
        self.assertEqual(first_cue["continuity_authority"], "base_v2a")
        self.assertEqual(first_cue["context_warnings"], [])
        self.assertFalse(plan["quality_certified"])
        self.assertFalse(plan["model_or_network_call"])

    def test_scene_two_transition_does_not_retroactively_change_scene_one(self):
        plan = plan_triplet()
        first, second = plan["scenes"]
        self.assertEqual(first["batches"][0]["target"][0]["address"]["self"], "em")
        self.assertEqual(second["batches"][0]["target"][0]["address"]["self"], "tôi")
        self.assertEqual(second["batches"][0]["target"][0]["continuity_authority"], "m02-distance")
        self.assertEqual(second["batches"][0]["target"][1]["address"]["self"], "anh")
        self.assertEqual(second["batches"][0]["target"][0]["address"]["other"], "anh")
        self.assertEqual(second["memory_state_at_scene_start"]["applied_event_ids"], ["m02-distance"])
        self.assertEqual(second["memory_state_at_scene_start"]["confirmed_aliases_untrusted"][0]["alias"], "Mây")
        self.assertEqual(first["batches"][0]["read_only_after"], [])
        self.assertEqual(second["batches"][0]["read_only_before"], [])
        self.assertEqual(first["address_rules_untrusted"][0]["self"], "em")
        self.assertEqual(second["address_rules_untrusted"][0]["self"], "tôi")

    def test_same_source_lf_crlf_produces_identical_replay_hash_and_plan(self):
        source, meta, journal = inputs()
        lf = source.replace(b"\r\n", b"\n")
        windows = lf.replace(b"\n", b"\r\n")
        self.assertNotEqual(hashlib.sha256(lf).hexdigest(),
                            hashlib.sha256(windows).hexdigest())
        self.assertEqual(create_memory_plan(lf, "srt", meta, journal),
                         create_memory_plan(windows, "srt", meta, journal))

    def test_source_content_timestamp_and_bom_mutations_fail_sha(self):
        source, meta, journal = inputs()
        for bad in (
            source.replace(b"almost stayed", b"never stayed"),
            source.replace(b"00:00:06,000", b"00:00:06,001"),
            b"\xef\xbb\xbf" + source,
        ):
            with self.subTest(bad=bad[:20]), self.assertRaises(ValueError):
                create_memory_plan(bad, "srt", meta, journal)

    def test_manifest_changed_summary_character_or_turn_not_reusable(self):
        source, meta, journal = inputs()
        cases = []
        a = deepcopy(meta);a["scenes"][0]["summary"] = "Altered invented plot";cases.append(a)
        a = deepcopy(meta);a["characters"][0]["name"] = "Other";cases.append(a)
        a = deepcopy(meta);a["scenes"][0]["turns"][0]["speaker"] = None;cases.append(a)
        for bad in cases:
            with self.subTest(bad=str(bad)[:50]), self.assertRaisesRegex(ValueError, "MEMORY_SOURCE_OR_CONTEXT_DRIFT"):
                create_memory_plan(source, "srt", bad, journal)

    def test_other_source_or_memory_provenance_cannot_steal_alias(self):
        source, meta, journal = inputs()
        changed=deepcopy(journal)
        changed["source_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "MEMORY_SOURCE_OR_CONTEXT_DRIFT"):
            create_memory_plan(source, "srt", meta, changed)
        changed=deepcopy(journal)
        changed["provenance"] = "other"
        with self.assertRaises(ValueError):
            create_memory_plan(source, "srt", meta, changed)

    def test_duplicate_event_id_and_reverse_scene_order_are_rejected(self):
        source, meta, journal = inputs()
        bad=deepcopy(journal);bad["events"][1]["id"] = bad["events"][0]["id"]
        with self.assertRaisesRegex(ValueError, "MEMORY_DUPLICATE_EVENT_ID"):
            create_memory_plan(source, "srt", meta, bad)
        bad=deepcopy(journal);bad["events"].reverse()
        with self.assertRaisesRegex(ValueError, "MEMORY_EVENTS_OUT_OF_SCENE_ORDER"):
            create_memory_plan(source, "srt", meta, bad)

    def test_unknown_scene_and_event_schema_rejected(self):
        source, meta, journal = inputs()
        bad=deepcopy(journal);bad["events"][0]["scene_id"]="future_scene"
        with self.assertRaisesRegex(ValueError, "MEMORY_UNKNOWN_SCENE"):
            create_memory_plan(source, "srt", meta, bad)
        bad=deepcopy(journal);bad["events"][0]["kind"]="auto_inferred"
        with self.assertRaises(ValueError):
            create_memory_plan(source, "srt", meta, bad)
        bad=deepcopy(journal);bad["events"][1]["extra"]="synthetic"
        with self.assertRaisesRegex(ValueError, "MEMORY_EVENT_SHAPE_INVALID"):
            create_memory_plan(source, "srt", meta, bad)

    def test_duplicate_alias_same_scene_or_across_characters_rejected(self):
        source, meta, journal = inputs()
        bad=deepcopy(journal)
        duplicate=deepcopy(bad["events"][0]);duplicate["id"]="m02-dup"
        bad["events"].insert(1,duplicate)
        with self.assertRaises(ValueError):
            create_memory_plan(source, "srt", meta, bad)
        bad=deepcopy(journal)
        duplicate=deepcopy(bad["events"][0])
        duplicate.update(id="m03-dup",scene_id="station_decision",character="minh")
        bad["events"].append(duplicate)
        with self.assertRaisesRegex(ValueError, "MEMORY_ALIAS_COLLISION_OR_LIMIT"):
            create_memory_plan(source, "srt", meta, bad)

    def test_cast_name_cannot_be_taken_as_an_alias(self):
        source, meta, journal = inputs()
        bad=deepcopy(journal);bad["events"][0]["alias"]="Minh"
        with self.assertRaisesRegex(ValueError, "MEMORY_ALIAS_COLLISION_OR_LIMIT"):
            create_memory_plan(source, "srt", meta, bad)
        bad=deepcopy(journal);bad["events"][0]["alias"]="linh"
        with self.assertRaisesRegex(ValueError, "MEMORY_ALIAS_COLLISION_OR_LIMIT"):
            create_memory_plan(source, "srt", meta, bad)

    def test_invalid_character_and_unreviewed_evidence_are_rejected(self):
        source, meta, journal = inputs()
        bad=deepcopy(journal);bad["events"][0]["character"]="untracked"
        with self.assertRaisesRegex(ValueError, "MEMORY_EVENT_UNKNOWN_CHARACTER"):
            create_memory_plan(source, "srt", meta, bad)
        bad=deepcopy(journal);bad["events"][1]["evidence"]="model_guessed"
        with self.assertRaisesRegex(ValueError, "MEMORY_EVENT_EVIDENCE_INVALID"):
            create_memory_plan(source, "srt", meta, bad)

    def test_multiple_address_changes_same_pair_and_scene_rejected(self):
        source, meta, journal = inputs()
        bad=deepcopy(journal)
        other=deepcopy(bad["events"][1]);other["id"]="m03-dup";other["other"]="ngài"
        bad["events"].append(other)
        with self.assertRaisesRegex(ValueError, "MEMORY_CONFLICTING_EVENTS_IN_SCENE"):
            create_memory_plan(source, "srt", meta, bad)

    def test_reject_noop_transition_and_illegal_pair(self):
        source, meta, journal = inputs()
        bad=deepcopy(journal)
        bad["events"][1].update(self="em", other="anh")
        with self.assertRaisesRegex(ValueError, "MEMORY_NOOP_ADDRESS_TRANSITION"):
            create_memory_plan(source, "srt", meta, bad)
        bad=deepcopy(journal);bad["events"][1]["addressee"]="linh"
        with self.assertRaisesRegex(ValueError, "MEMORY_ADDRESS_PAIR_INVALID"):
            create_memory_plan(source, "srt", meta, bad)

    def test_alias_revocation_is_effective_only_in_second_scene(self):
        source, meta, journal = inputs()
        bad=deepcopy(journal)
        rev={"id":"m03-revoke","scene_id":"station_decision","kind":"alias_revoked",
             "character":"linh","alias":"Mây","evidence":"fixture_authored",
             "note":"Deliberate test-only alias retirement"}
        bad["events"].append(rev)
        plan=create_memory_plan(source,"srt",meta,bad)
        self.assertEqual(len(plan["scenes"][0]["memory_state_at_scene_start"]["confirmed_aliases_untrusted"]),1)
        self.assertEqual(len(plan["scenes"][1]["memory_state_at_scene_start"]["confirmed_aliases_untrusted"]),0)
        bad=deepcopy(journal);bad["events"][0]["kind"]="alias_revoked"
        with self.assertRaisesRegex(ValueError, "MEMORY_REVOKE_UNCONFIRMED_ALIAS"):
            create_memory_plan(source,"srt",meta,bad)

    def test_unknown_pronoun_pair_stays_unresolved_despite_memory(self):
        source,meta,journal=inputs()
        meta["address_rules"]=[]
        journal["base_context_sha256"]=_stable_digest(meta)
        plan=create_memory_plan(source,"srt",meta,journal)
        first=plan["scenes"][0]["batches"][0]["target"]
        second=plan["scenes"][1]["batches"][0]["target"]
        self.assertEqual(first[0]["context_warnings"],["UNCONFIRMED_PRONOUN_PAIR"])
        self.assertEqual(second[0]["context_warnings"],[])
        self.assertEqual(second[1]["context_warnings"],["UNCONFIRMED_PRONOUN_PAIR"])

    def test_timeline_with_three_scenes_preserves_confirmed_state_forward_only(self):
        source, meta, journal=inputs()
        scene1=deepcopy(meta["scenes"][0])
        scene1["cue_end"]=4;scene1["turns"]=scene1["turns"][:4]
        scene2=deepcopy(meta["scenes"][1])
        scene2["id"]="middle";scene2["cue_start"]=5;scene2["cue_end"]=8
        scene2["turns"]=meta["scenes"][0]["turns"][4:]+meta["scenes"][1]["turns"][:2]
        scene3=deepcopy(meta["scenes"][1])
        scene3["cue_start"]=9;scene3["turns"]=scene3["turns"][2:]
        meta["scenes"]=[scene1,scene2,scene3]
        journal["base_context_sha256"]=_stable_digest(meta)
        plan=create_memory_plan(source,"srt",meta,journal)
        self.assertEqual(len(plan["scenes"]),3)
        self.assertEqual(plan["scenes"][0]["batches"][0]["target"][0]["address"]["self"],"em")
        self.assertEqual(plan["scenes"][1]["batches"][0]["target"][0]["address"]["self"],"em")
        self.assertEqual(plan["scenes"][2]["batches"][0]["target"][0]["address"]["self"],"tôi")

    def test_memory_zero_event_plan_still_protects_base_rules(self):
        source,meta,journal=inputs()
        journal["events"]=[]
        plan=create_memory_plan(source,"srt",meta,journal)
        self.assertEqual(plan["applied_events"],0)
        self.assertEqual(plan["address_transitions"],0)
        for scene in plan["scenes"]:
            self.assertEqual(scene["memory_state_at_scene_start"]["applied_event_ids"],[])
        self.assertEqual(plan["scenes"][1]["batches"][0]["target"][0]["address"]["self"],"em")

    def test_srt_vtt_equivalent_source_semantics_but_separate_source_sha(self):
        source,meta,journal=inputs()
        vtt=render(parse_cues(source,"srt"),"vtt")
        meta["source_sha256"]=_canonical_source_sha256(vtt)
        journal["source_sha256"]=_canonical_source_sha256(vtt)
        journal["base_context_sha256"]=_stable_digest(meta)
        plan=create_memory_plan(vtt,"vtt",meta,journal)
        self.assertEqual(plan["format"],"vtt")
        self.assertEqual(plan["scenes"][0]["batches"][0]["target"][0]["start_ms"],3000)
        self.assertNotEqual(plan["source_sha256"],_canonical_source_sha256(source))

    def test_inspect_uses_real_time_cps_and_does_not_claim_semantic_pass(self):
        source,meta,journal=inputs()
        out=inspect_memory(source,"srt",meta,journal,translation_map())
        self.assertEqual(out["cue_count"],12)
        self.assertEqual(out["readability"]["flagged_cues"],0)
        self.assertEqual(out["continuity_unknown_count"],0)
        self.assertFalse(out["quality_certified"])
        self.assertEqual(out["human_semantic_review"],"REQUIRED")
        self.assertTrue(out["no_subtitle_rewrite"])
        revised=translation_map();revised["7"]="Một câu rất dài và thật sự vượt quá ngân sách đọc 2,5 giây."
        report=inspect_memory(source,"srt",meta,journal,revised)
        self.assertIn("READING_SPEED",report["readability"]["flags"][0]["codes"])

    def test_inspect_refuses_incomplete_or_mojibake_translations(self):
        source,meta,journal=inputs()
        changed=translation_map();del changed["12"]
        with self.assertRaises(ValueError):
            inspect_memory(source,"srt",meta,journal,changed)
        changed=translation_map();changed["1"]="kh├┤ng"
        with self.assertRaisesRegex(ValueError,"CONTEXT_TRANSLATION_CP437_SUSPECTED"):
            inspect_memory(source,"srt",meta,journal,changed)

    def test_cli_prepare_requires_explicit_consent_and_never_overwrites(self):
        with TemporaryDirectory() as d:
            dest=Path(d)/"plan.json"
            args=["memory","prepare","--input",str(SRT),"--context",str(CONTEXT),
                  "--memory",str(MEMORY),"--out",str(dest)]
            with patch.object(sys,"argv",args),self.assertRaises(SystemExit):
                main()
            self.assertFalse(dest.exists())
            with patch.object(sys,"argv",[*args,"--confirm",CONFIRM]),redirect_stdout(io.StringIO()) as result:
                self.assertEqual(main(),0)
            self.assertIn("CONTEXT_V2B_PLAN_PREPARED scenes=2 cues=12 events=2 no_model_call",result.getvalue())
            self.assertNotIn("Linh",result.getvalue())
            self.assertNotIn(str(SRT),result.getvalue())
            self.assertEqual(json.loads(dest.read_text(encoding="utf-8"))["applied_events"],2)
            with patch.object(sys,"argv",[*args,"--confirm",CONFIRM]),self.assertRaises(SystemExit):
                main()

    def test_cli_inspect_stdout_has_no_caption_text_or_paths(self):
        with TemporaryDirectory() as d:
            translations=Path(d)/"translation.json"
            translations.write_text(json.dumps(translation_map()),encoding="utf-8")
            args=["memory","inspect","--input",str(SRT),"--context",str(CONTEXT),
                  "--memory",str(MEMORY),"--translations",str(translations)]
            with patch.object(sys,"argv",args),redirect_stdout(io.StringIO()) as output:
                self.assertEqual(main(),0)
            obj=json.loads(output.getvalue())
            self.assertEqual(obj["schema"],"P2-AISUB.memory-v2b-inspection-v1")
            self.assertNotIn("Đã đến",output.getvalue())
            self.assertNotIn(str(SRT),output.getvalue())
            self.assertNotIn("Mây",output.getvalue())

    def test_repo_source_contains_no_model_network_or_host_runner(self):
        import inspect
        import context_memory_v2b
        source=inspect.getsource(context_memory_v2b)
        for needle in ("subprocess.", "requests.", "socket.", "urllib.request",
                       "generateContent(", "agy -p", "api_key", "adb "):
            self.assertNotIn(needle,source)


if __name__ == "__main__":
    unittest.main()
