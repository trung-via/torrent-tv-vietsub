from __future__ import annotations
import copy
import unittest
import blind_semantic_gate as gate


def fixture():
    rows=[]
    for w,(lo,hi) in gate.EXPECTED_RANGES.items():
        for idx in range(lo,lo+30):
            rows.append({'window':w,'id':idx,'timestamp':'00:00:01,000 --> 00:00:02,000',
                         'english':'This is a synthetic source',
                         'variants':{'A':'Câu thử A','B':'Câu thử B','C':'Câu thử C'}})
    return {'schema':gate.SCHEMA,'source_sha256':gate.SOURCE_SHA,'rows':rows}


def finished():
    doc=fixture(); x=gate.make_blank(doc)
    x['reviewer'].update(id='human-reviewer-1', bilingual_qualification='English-Vietnamese translator',
                         date='2026-11-10',assessment_method='INDEPENDENT_HUMAN_BILINGUAL',
                         declaration=gate.NO_KEY_DECLARATION)
    for row in x['rows']:
        row['scores']={k:0 for k in 'ABC'}
    return doc,x

class BlindGateTests(unittest.TestCase):
    def test_valid_90x3(self):
        x=gate.validate_blind(fixture());self.assertEqual(x['rows'],90);self.assertEqual(x['ratings_expected'],270)
    def test_hard_pin_source(self):
        a=fixture();a['source_sha256']='bad'
        with self.assertRaisesRegex(gate.ReviewError,'SOURCE_SHA_MISMATCH'):gate.validate_blind(a)
    def test_no_duplicate_cue(self):
        a=fixture();a['rows'][1]['id']=a['rows'][0]['id']
        with self.assertRaisesRegex(gate.ReviewError,'BLIND_IDS_DUPLICATED'):gate.validate_blind(a)
    def test_no_less_than_90(self):
        a=fixture();a['rows'].pop()
        with self.assertRaisesRegex(gate.ReviewError,'BLIND_ROW_COUNT'):gate.validate_blind(a)
    def test_no_label_leak(self):
        a=fixture();a['rows'][0]['variants']={'BASE120':'Hello','B':'Hey','C':'Hi'}
        with self.assertRaisesRegex(gate.ReviewError,'MASKED'):gate.validate_blind(a)
    def test_empty_submit_incomplete(self):
        a=fixture();x=gate.make_blank(a);x['reviewer'].update(id='human',bilingual_qualification='translator',date='now',assessment_method='INDEPENDENT_HUMAN_BILINGUAL',declaration=gate.NO_KEY_DECLARATION)
        r=gate.evaluate(a,x);self.assertEqual(r['status'],'INCOMPLETE');self.assertEqual(r['missing_count'],270)
    def test_full_submit_scoring(self):
        a,x=finished();r=gate.evaluate(a,x,True);self.assertEqual(r['scored_count'],270);self.assertEqual(r['meaning_risk_ratings'],0)
    def test_missing_independence_declaration(self):
        a,x=finished();x['reviewer']['declaration']='yes'
        with self.assertRaisesRegex(gate.ReviewError,'DECLARATION'):gate.evaluate(a,x)
    def test_other_engine_cannot_claim_independent_human(self):
        a,x=finished();x['reviewer']['assessment_method']='SAME_CHATGPT_BRAIN'
        with self.assertRaisesRegex(gate.ReviewError,'METHOD_DECLARATION'):gate.evaluate(a,x)
    def test_cannot_change_masked_sheet(self):
        a,x=finished();a['rows'][0]['english']='changed'
        with self.assertRaisesRegex(gate.ReviewError,'PIN_MISMATCH'):gate.evaluate(a,x)
    def test_cannot_omit_masked_variant(self):
        a,x=finished();x['rows'][0]['scores'].pop('C')
        with self.assertRaisesRegex(gate.ReviewError,'A_B_C_REQUIRED'):gate.evaluate(a,x)
    def test_cannot_duplicate_response_id(self):
        a,x=finished();x['rows'][0]['id']=x['rows'][1]['id']
        with self.assertRaisesRegex(gate.ReviewError,'IDS_CHANGED'):gate.evaluate(a,x)
    def test_invalid_score_bool_rejected(self):
        a,x=finished();x['rows'][0]['scores']['A']=True
        with self.assertRaisesRegex(gate.ReviewError,'SCORE_INVALID'):gate.evaluate(a,x)
    def test_major_error_requires_notes(self):
        a,x=finished();x['rows'][0]['scores']['A']=3
        with self.assertRaisesRegex(gate.ReviewError,'RISK_NOTES_REQUIRED'):gate.evaluate(a,x)
        x['rows'][0]['notes']='Incorrect named speaker';r=gate.evaluate(a,x);self.assertEqual(r['major_ratings'],1)
    def test_uncertainty_not_a_pass(self):
        a,x=finished();x['rows'][0]['scores']['B']='?';x['rows'][0]['notes']='Requires scene video'
        r=gate.evaluate(a,x);self.assertEqual(r['uncertain_ratings'],1);self.assertTrue(r['quality_gate'].startswith('HOLD'))
    def test_incomplete_blocks_unblind(self):
        a,x=finished();x['rows'][0]['scores']['A']=None
        k={'mapping':{str(w):{'A':'BASE120','B':'LEAN120','C':'ADAPTIVE'} for w in (1,2,3)}}
        with self.assertRaisesRegex(gate.ReviewError,'REVIEW_NOT_COMPLETE'):gate.unblind(a,x,k)
    def test_invalid_key_rejected(self):
        a,x=finished();k={'mapping':{str(w):{'A':'BASE120','B':'BASE120','C':'ADAPTIVE'} for w in (1,2,3)}}
        with self.assertRaisesRegex(gate.ReviewError,'PRIVATE_MAPPING'):gate.unblind(a,x,k)
    def test_complete_unblind_aggregates_without_dialogue(self):
        a,x=finished();k={'mapping':{str(w):{'A':'BASE120','B':'LEAN120','C':'ADAPTIVE'} for w in (1,2,3)}}
        r=gate.unblind(a,x,k)
        self.assertEqual(sum(r['arm_counts']['BASE120'].values()),90)
        self.assertEqual(r['mean_score_excluding_uncertain']['LEAN120'],0)
        self.assertNotIn('English',str(r));self.assertNotIn('Câu thử',str(r))
        self.assertEqual(r['promotion'],'NOT_AUTHORIZED_WITHOUT_REPEATED_MATCHED_ALL_IN_SPEED_AND_SEMANTIC_ADJUDICATION')

class CommandLineGateTests(unittest.TestCase):
    def test_reject_missing_owner_pin(self):
        import tempfile, pathlib, subprocess, sys, json
        a,x=finished()
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d)
            (p/'blind.json').write_text(json.dumps(a),encoding='utf-8')
            (p/'score.json').write_text(json.dumps(x),encoding='utf-8')
            result=subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('blind_semantic_gate.py')),
                                   'validate','--blind',str(p/'blind.json'),'--scores',str(p/'score.json')],capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
            self.assertIn('OWNER_PINNED_BLIND_SHA_REQUIRED',result.stdout)
    def test_accept_exact_owner_pin(self):
        import tempfile, pathlib, subprocess, sys, json
        a,x=finished()
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d)
            (p/'blind.json').write_text(json.dumps(a),encoding='utf-8')
            (p/'score.json').write_text(json.dumps(x),encoding='utf-8')
            result=subprocess.run([sys.executable,str(pathlib.Path(__file__).with_name('blind_semantic_gate.py')),
                                   'validate','--blind',str(p/'blind.json'),'--scores',str(p/'score.json'),
                                   '--expected-blind-sha',gate.validate_blind(a)['blind_sha256']],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout)
            self.assertIn('COMPLETE_REVIEWER_DECLARED_INDEPENDENT_NOT_ATTESTED',result.stdout)

if __name__=="__main__":
    unittest.main()
