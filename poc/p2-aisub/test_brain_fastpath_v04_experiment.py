"""Synthetic public-domain-like test text only; no movie material or network."""
import io
import json
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from brain_fastpath_v04_experiment import (
    ARMS, ExperimentBlocked, _ranges, _risk, _split, _translated,
    finish, main, phase, plan, start, summary,
)
from cue_pipeline import Cue, parse_cues


def make_srt(n=480, risky=False):
    parts=[]
    for i in range(1,n+1):
        start=2000+i*3100
        end=start+2200
        def stamp(ms):
            h,ms=divmod(ms,3600000)
            m,ms=divmod(ms,60000)
            s,ms=divmod(ms,1000)
            return f'{h:02d}:{m:02d}:{s:02d},{ms:03d}'
        text = 'Please bring the small blue box.'
        if risky and i%3==0: text="Don't you trust her?"
        if risky and i%7==0: text='- Did you hear that?\n- Yes, I did.'
        parts.append(f'{i}\n{stamp(start)} --> {stamp(end)}\n{text}')
    return ('\n\n'.join(parts)+'\n').encode('utf-8')


def answer(start, end):
    return ''.join(f'{i}|Tôi sẽ mang hộp xanh đến.\n' for i in range(start,end+1)).encode('utf-8')


class V04Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.source=self.root/'synthetic.en.srt'
        self.source.write_bytes(make_srt())
        self.work=self.root/'brain-study'

    def planned(self, risky=False):
        if risky:
            self.source.write_bytes(make_srt(risky=True))
        return plan(self.source,self.work,'1-160,161-320,321-480')

    def test_planner_creates_exactly_nine_trials_and_no_provider(self):
        report=self.planned()
        self.assertEqual((report['trials'],report['windows'],report['model_calls']),(9,3,0))
        m=json.loads((self.work/'manifest.json').read_text())
        self.assertEqual({a['arm'] for a in m['trials']},set(ARMS))
        self.assertEqual(len({a['id'] for a in m['trials']}),9)
        self.assertTrue(all((p/'prompt_01.txt').is_file() for p in self.work.iterdir() if p.is_dir()))
        self.assertEqual(summary(self.work)['status'],'INCOMPLETE_NOT_COMPARABLE')
        self.assertEqual(summary(self.work)['winner'],'NONE')

    def test_adaptive_risky_and_normal_are_deterministically_different(self):
        easy=parse_cues(make_srt(),'srt')[:160]
        hard=parse_cues(make_srt(risky=True),'srt')[:160]
        ea=_split(easy,'ADAPTIVE')
        ha=_split(hard,'ADAPTIVE')
        self.assertEqual(len(ea[0][0]),160)
        self.assertLessEqual(len(ha[0][0]),100)
        self.assertEqual([x.number for v,_ in ha for x in v],list(range(1,161)))
        self.assertGreater(sum(_risk(x)>0 for x in hard),sum(_risk(x)>0 for x in easy))

    def test_global_rules_identical_for_all_arms_and_tamper_refused(self):
        self.planned()
        m=json.loads((self.work/'manifest.json').read_text())
        b=(self.work/'GLOBAL_INSTRUCTIONS.txt').read_bytes()
        self.assertEqual(m['global_rules_sha256'],__import__('hashlib').sha256(b).hexdigest())
        (self.work/'GLOBAL_INSTRUCTIONS.txt').write_text('ALTERED')
        with self.assertRaisesRegex(ExperimentBlocked,'V04_GLOBAL_RULES_CHANGED'):
            start(self.work,self.source,'W01-BASE120','CHATGPT_BRAIN_GPT6_INTERACTIVE')

    def test_1761_cue_synthetic_film_plans_safe_no_provider(self):
        self.source.write_bytes(make_srt(n=1761,risky=True))
        result=plan(self.source,self.work,'1-160,561-720,1081-1240')
        self.assertEqual(result['model_calls'],0)
        self.assertEqual(result['trials'],9)
        self.assertTrue(all(t['prompts'][0]['first']>=1 for t in json.loads((self.work/'manifest.json').read_text())['trials']))

    def test_same_source_targets_baseline_lean(self):
        self.planned()
        m=json.loads((self.work/'manifest.json').read_text())
        b=next(t for t in m['trials'] if t['id']=='W01-BASE120')
        l=next(t for t in m['trials'] if t['id']=='W01-LEAN120')
        self.assertEqual([(p['first'],p['last']) for p in b['prompts']],[(p['first'],p['last']) for p in l['prompts']])
        self.assertEqual([(p['first'],p['last']) for p in b['prompts']],[(1,120),(121,160)])

    def test_glossary_pinned_same_in_all_prompts(self):
        g=self.root/'glossary.txt';g.write_text('the box = chiếc hộp',encoding='utf-8')
        plan(self.source,self.work,'1-160,161-320,321-480',g)
        m=json.loads((self.work/'manifest.json').read_text())
        self.assertEqual(m['glossary_sha256'],__import__('hashlib').sha256(g.read_bytes()).hexdigest())
        for t in m['trials']:
            self.assertIn('chiếc hộp',(self.work/t['id']/t['prompts'][0]['file']).read_text())

    def test_repeat_plan_does_not_mutate_old_private_files(self):
        self.planned()
        old=(self.work/'manifest.json').read_bytes()
        with self.assertRaisesRegex(ExperimentBlocked,'V04_WORKDIR_ALREADY_EXISTS'):
            self.planned()
        self.assertEqual(old,(self.work/'manifest.json').read_bytes())

    def test_strict_window_constraints(self):
        for bad in ('1-160,160-319,321-480','1-159,160-319,321-480','1-160,161-320',
                    '0-159,161-320,321-480','a-b,161-320,321-480'):
            with self.subTest(ranges=bad),self.assertRaises(ExperimentBlocked):
                _ranges(bad,480)

    def test_prompt_tamper_blocks_start(self):
        self.planned()
        p=self.work/'W01-BASE120'/'prompt_01.txt'
        p.write_text('TAMPER!')
        with self.assertRaisesRegex(ExperimentBlocked,'V04_PROMPT_CHANGED'):
            start(self.work,self.source,'W01-BASE120','CHATGPT_BRAIN_GPT6_INTERACTIVE')
        self.assertFalse((self.work/'W01-BASE120'/'timer.json').exists())

    def test_source_sha_drift_blocks_start(self):
        self.planned()
        self.source.write_bytes(make_srt(risky=True))
        with self.assertRaisesRegex(ExperimentBlocked,'V04_SOURCE_SHA_CHANGED'):
            start(self.work,self.source,'W01-BASE120','CHATGPT_BRAIN_GPT6_INTERACTIVE')

    def test_gemini_cannot_be_spoofed_as_brain(self):
        self.planned()
        with self.assertRaisesRegex(ExperimentBlocked,'V04_BRAIN_ONLY_EXPERIMENT'):
            start(self.work,self.source,'W01-BASE120','ANTIGRAVITY_GEMINI')

    def test_timer_phase_order_and_no_reruns(self):
        self.planned()
        start(self.work,self.source,'W01-BASE120','CHATGPT_BRAIN_GPT6_INTERACTIVE')
        with self.assertRaisesRegex(ExperimentBlocked,'V04_PHASE_ORDER_REQUIRED'):
            phase(self.work,self.source,'W01-BASE120','qa','begin')
        phase(self.work,self.source,'W01-BASE120','translation','begin')
        with self.assertRaises(ExperimentBlocked):
            phase(self.work,self.source,'W01-BASE120','ingest','begin')
        phase(self.work,self.source,'W01-BASE120','translation','end')
        with self.assertRaises(ExperimentBlocked):
            phase(self.work,self.source,'W01-BASE120','translation','begin')
        phase(self.work,self.source,'W01-BASE120','ingest','begin')
        phase(self.work,self.source,'W01-BASE120','ingest','end')
        phase(self.work,self.source,'W01-BASE120','qa','begin')
        phase(self.work,self.source,'W01-BASE120','qa','end')
        phase(self.work,self.source,'W01-BASE120','repair','skip')
        report=json.loads((self.work/'W01-BASE120'/'timer.json').read_text())
        self.assertEqual(set(report['phases']),{'translation','ingest','qa','repair'})
        self.assertEqual(report['phases']['repair'],0.0)

    def _timed(self,trial='W01-BASE120'):
        start(self.work,self.source,trial,'CHATGPT_BRAIN_GPT6_INTERACTIVE')
        for s in ('translation','ingest','qa'):
            phase(self.work,self.source,trial,s,'begin')
            phase(self.work,self.source,trial,s,'end')
        phase(self.work,self.source,trial,'repair','skip')

    def test_finish_real_user_supplied_tsv_only_no_fake_winner(self):
        self.planned()
        self._timed()
        out=self.root/'output.tsv';out.write_bytes(answer(1,160))
        receipt=finish(self.work,self.source,'W01-BASE120',out)
        self.assertEqual(receipt['status'],'STOPPED_STRUCTURAL_ONLY')
        self.assertEqual(receipt['semantic_review'],'NOT_INDEPENDENTLY_REVIEWED')
        self.assertFalse(receipt['default_change_authorized'])
        self.assertEqual(summary(self.work)['finished_trials'],1)
        self.assertEqual(summary(self.work)['winner'],'NONE')
        before=(self.work/'W01-BASE120'/'timer.json').read_bytes()
        with self.assertRaises(ExperimentBlocked):
            finish(self.work,self.source,'W01-BASE120',out)
        self.assertEqual(before,(self.work/'W01-BASE120'/'timer.json').read_bytes())

    def test_incomplete_translation_rejected_before_time_frozen(self):
        self.planned();self._timed()
        out=self.root/'broken.tsv';out.write_bytes(answer(1,159))
        with self.assertRaisesRegex(ExperimentBlocked,'V04_TRANSLATED_CUE_COUNT_MISMATCH'):
            finish(self.work,self.source,'W01-BASE120',out)
        self.assertEqual(json.loads((self.work/'W01-BASE120'/'timer.json').read_text())['state'],'RUNNING')

    def test_wrong_id_duplicate_and_empty_translation_rejected(self):
        sample=parse_cues(make_srt(2),'srt')
        for raw in (b'1|a\n1|b\n',b'1|a\n3|b\n',b'1|\n2|a\n',b'1|a\n'):
            with self.subTest(raw=raw),self.assertRaises(ExperimentBlocked):
                _translated(raw,sample)

    def test_speaker_and_markup_guards(self):
        cues=(Cue(1,1000,3000,'<i>- Hello</i>\n- Bye'),)
        with self.assertRaisesRegex(ExperimentBlocked,'V04_TRANSLATED_MARKUP_LOST'):
            _translated(b'1|- Xin chao\\n- Tam biet\n',cues)
        with self.assertRaisesRegex(ExperimentBlocked,'V04_SPEAKER_BOUNDARY_LOST'):
            _translated(b'1|<i>Xin chao</i>\n',cues)

    def test_invalid_vtt_stops_safely(self):
        self.source=self.root/'synthetic.en.vtt'
        self.source.write_bytes(b'WEBVTT\n\n')
        with self.assertRaisesRegex(ExperimentBlocked,'V04_SRT_ONLY_EXPERIMENT'):
            self.planned()

    def test_no_private_path_or_text_printed_by_cli(self):
        cap=io.StringIO()
        with redirect_stdout(cap):
            rc=main(['plan','--source',str(self.source),'--workdir',str(self.work),
                     '--ranges','1-160,161-320,321-480'])
        self.assertEqual(rc,0)
        self.assertNotIn(str(self.root),cap.getvalue())
        self.assertNotIn('Please bring',cap.getvalue())
        self.assertEqual(json.loads(cap.getvalue())['model_calls'],0)

    def test_cli_rejects_bad_ranges_with_sanitized_error(self):
        cap=io.StringIO()
        with redirect_stdout(cap):
            rc=main(['plan','--source',str(self.source),'--workdir',str(self.work),'--ranges','invalid'])
        self.assertEqual(rc,2)
        self.assertEqual(json.loads(cap.getvalue())['error_code'],'V04_WINDOW_FORMAT')
        self.assertNotIn(str(self.source),cap.getvalue())

    def test_stage_timer_missing_repair_blocks_finish(self):
        self.planned()
        start(self.work,self.source,'W01-BASE120','CHATGPT_BRAIN_GPT6_INTERACTIVE')
        for s in ('translation','ingest','qa'):
            phase(self.work,self.source,'W01-BASE120',s,'begin')
            phase(self.work,self.source,'W01-BASE120',s,'end')
        f=self.root/'out.tsv';f.write_bytes(answer(1,160))
        with self.assertRaisesRegex(ExperimentBlocked,'V04_MISSING_MEASURED_PHASES'):
            finish(self.work,self.source,'W01-BASE120',f)

    def test_source_manifest_contains_no_subtitle_or_absolute_path(self):
        self.planned(risky=True)
        m=(self.work/'manifest.json').read_text()
        self.assertNotIn('Don\'t',m)
        self.assertNotIn(str(self.root),m)
        self.assertIn('source_sha256',m)


if __name__=='__main__':
    unittest.main()
