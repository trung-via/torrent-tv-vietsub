"""Torrent TV P2-AISUB: offline, privacy-preserving blind bilingual review gate.

No model, network, subtitle upload, or reviewer identity attestation.
Receipts deliberately omit private English/Vietnamese dialogue and reviewer notes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from collections import Counter

SCHEMA = 'torrent-tv-v04-blind-90-v1'
SCORE_SCHEMA = 'torrent-tv-v04-blind-review-score-v1'
SOURCE_SHA = '76b857688ed6ab1f279190d23c54e3d5697eb91870178637342fd0874996ea8a'
EXPECTED_RANGES = {1:(181,340), 2:(561,720), 3:(1081,1240)}
NO_KEY_DECLARATION = 'I have not seen the arm key, self-review findings, or candidate repairs'

class ReviewError(ValueError):
    pass


def canonical(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',',':')).encode('utf-8')


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def _load(path):
    p=Path(path)
    if p.stat().st_size > 2_000_000:
        raise ReviewError('INPUT_TOO_LARGE')
    try: return json.loads(p.read_text('utf-8'))
    except (UnicodeError, json.JSONDecodeError): raise ReviewError('INVALID_JSON_UTF8') from None


def _save_new(path, value):
    with Path(path).open('x', encoding='utf-8', newline='\n') as h:
        h.write(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)+'\n')


def validate_blind(doc):
    if not isinstance(doc,dict) or doc.get('schema') != SCHEMA:
        raise ReviewError('BLIND_SCHEMA_MISMATCH')
    if doc.get('source_sha256') != SOURCE_SHA:
        raise ReviewError('SOURCE_SHA_MISMATCH')
    rows=doc.get('rows')
    if not isinstance(rows,list) or len(rows)!=90:
        raise ReviewError('BLIND_ROW_COUNT_NOT_90')
    ids=[]
    for row in rows:
        if not isinstance(row,dict):raise ReviewError('INVALID_BLIND_ROW')
        win=row.get('window'); i=row.get('id')
        if type(win)!=int or win not in EXPECTED_RANGES or type(i)!=int:
            raise ReviewError('BLIND_WINDOW_OR_ID_INVALID')
        lo,hi=EXPECTED_RANGES[win]
        if not lo<=i<=hi:raise ReviewError('BLIND_ID_OUTSIDE_WINDOW')
        if not isinstance(row.get('english'),str) or not row['english'].strip():
            raise ReviewError('BLIND_ENGLISH_REQUIRED')
        if not isinstance(row.get('timestamp'),str) or '-->' not in row['timestamp']:
            raise ReviewError('BLIND_TIMESTAMP_REQUIRED')
        variants=row.get('variants')
        if not isinstance(variants,dict) or set(variants)!=set('ABC'):
            raise ReviewError('BLIND_THREE_MASKED_VARIANTS_REQUIRED')
        if any(not isinstance(t,str) or not t.strip() for t in variants.values()):
            raise ReviewError('BLIND_EMPTY_TRANSLATION')
        ids.append((win,i))
    if len(set(ids))!=90 or ids!=sorted(ids):
        raise ReviewError('BLIND_IDS_DUPLICATED_OR_UNORDERED')
    if any(sum(1 for w,_ in ids if w==i)!=30 for i in (1,2,3)):
        raise ReviewError('BLIND_WINDOW_NOT_30')
    return {'source_sha256':SOURCE_SHA,'blind_sha256':sha256_bytes(canonical(doc)),
            'rows':90,'ratings_expected':270,'windows':3}


def make_blank(doc):
    v=validate_blind(doc)
    return {
        'schema': SCORE_SCHEMA,
        'source_sha256':SOURCE_SHA,
        'blind_sha256':v['blind_sha256'],
        'reviewer': {'id':'', 'bilingual_qualification':'', 'date':'',
                     'assessment_method':'', 'declaration':''},
        'rows':[{'window':r['window'],'id':r['id'], 'scores': {'A':None,'B':None,'C':None},'notes':''}
                for r in doc['rows']],
        'reviewer_instructions':'Score 0 accurate; 1 minor style; 2 meaning risk; 3 major meaning/speaker issue; ? uncertain. Complete every A/B/C value. For ? or score >=2, explain in notes. Do not open mapping, same-Brain triage or candidate patches before submission.'
    }


def evaluate(doc,submission,require_full=False):
    v=validate_blind(doc)
    if not isinstance(submission,dict) or submission.get('schema')!=SCORE_SCHEMA:
        raise ReviewError('REVIEW_SCHEMA_MISMATCH')
    if submission.get('source_sha256')!=SOURCE_SHA or submission.get('blind_sha256')!=v['blind_sha256']:
        raise ReviewError('REVIEW_PIN_MISMATCH')
    reviewer=submission.get('reviewer')
    if not isinstance(reviewer,dict):raise ReviewError('REVIEWER_METADATA_REQUIRED')
    if not isinstance(reviewer.get('id'),str) or not reviewer['id'].strip() or not isinstance(reviewer.get('bilingual_qualification'),str) or not reviewer['bilingual_qualification'].strip():
        raise ReviewError('REVIEWER_ID_AND_QUALIFICATION_REQUIRED')
    if reviewer.get('declaration') != NO_KEY_DECLARATION:
        raise ReviewError('REVIEWER_BLIND_DECLARATION_REQUIRED')
    if reviewer.get('assessment_method') != 'INDEPENDENT_HUMAN_BILINGUAL':
        raise ReviewError('INDEPENDENT_BILINGUAL_METHOD_DECLARATION_REQUIRED')
    if not isinstance(reviewer.get('date'),str) or not reviewer['date'].strip():
        raise ReviewError('REVIEW_DATE_REQUIRED')
    rows=submission.get('rows')
    if not isinstance(rows,list) or len(rows)!=90:raise ReviewError('REVIEW_ROW_COUNT_MISMATCH')
    expected=[(r['window'],r['id']) for r in doc['rows']]
    actual=[]; scores_by_window={i:Counter() for i in (1,2,3)};missing=0;major=0;meaning_risk=0;uncertain=0
    for row in rows:
        if not isinstance(row,dict):raise ReviewError('INVALID_REVIEW_ROW')
        w=row.get('window'); idx=row.get('id')
        if type(w)!=int or w not in EXPECTED_RANGES or type(idx)!=int:raise ReviewError('REVIEW_ROW_ID_INVALID')
        actual.append((w,idx))
        scores=row.get('scores')
        if not isinstance(scores,dict) or set(scores)!=set('ABC'):raise ReviewError('REVIEW_SCORES_A_B_C_REQUIRED')
        notes=row.get('notes','')
        if not isinstance(notes,str):raise ReviewError('REVIEW_NOTES_INVALID')
        for s in scores.values():
            if s is None:missing+=1;continue
            if s != '?' and (type(s)!=int or s not in (0,1,2,3)):
                raise ReviewError('REVIEW_SCORE_INVALID')
            if (s=='?' or (type(s)==int and s>=2)) and not notes.strip():
                raise ReviewError('REVIEW_RISK_NOTES_REQUIRED')
            scores_by_window[w][str(s)]+=1
            if s=='?':uncertain+=1
            elif s==2:meaning_risk+=1
            elif s==3:major+=1
    if actual!=expected:raise ReviewError('REVIEW_IDS_CHANGED_OR_DUPLICATE')
    if require_full and missing:raise ReviewError('REVIEW_NOT_COMPLETE')
    return {'status': 'COMPLETE_REVIEWER_DECLARED_INDEPENDENT_NOT_ATTESTED' if not missing else 'INCOMPLETE',
            'source_sha256':SOURCE_SHA,'blind_sha256':v['blind_sha256'],
            'reviewer_id_hash':sha256_bytes(reviewer['id'].encode('utf-8')),
            'reviewer_attestation':'DECLARED_NOT_INDEPENDENTLY_VERIFIED',
            'scored_count':270-missing,'expected_count':270,'missing_count':missing,
            'meaning_risk_ratings':meaning_risk,'major_ratings':major,'uncertain_ratings':uncertain,
            'per_window_counts':{str(k):dict(v) for k,v in scores_by_window.items()},
            'arm_winner':'NONE','speed_winner':'NONE',
            'quality_gate':'HOLD_INDEPENDENT_REVIEW_AND_ADJUDICATION' if missing or major or meaning_risk or uncertain else 'REVIEW_SCORING_COMPLETE_NOT_PRODUCTION_ACCEPTED'}


def unblind(doc,submission,key, *, expected_key_sha=None):
    # The A/B/C map has only a few possible permutations; NEVER put its SHA
    # or actual mapping in a public repository/CI receipt. The owner must
    # privately pin the exact key BEFORE the reviewer receives the sheet.
    if not isinstance(expected_key_sha, str) or not expected_key_sha:
        raise ReviewError('OWNER_PINNED_PRIVATE_KEY_SHA_REQUIRED')
    if not isinstance(key, dict) or sha256_bytes(canonical(key)) != expected_key_sha:
        raise ReviewError('OWNER_PINNED_PRIVATE_KEY_SHA_MISMATCH')
    summary=evaluate(doc,submission,True)
    mapping=key.get('mapping') if isinstance(key,dict) else None
    if not isinstance(mapping,dict) or set(mapping)!=set(['1','2','3']):
        raise ReviewError('INVALID_PRIVATE_MAPPING')
    for w in ('1','2','3'):
        if not isinstance(mapping[w],dict) or set(mapping[w])!=set('ABC') or set(mapping[w].values())!=set(['BASE120','LEAN120','ADAPTIVE']):
            raise ReviewError('INVALID_WINDOW_PRIVATE_MAPPING')
    counts={arm:Counter() for arm in ('BASE120','LEAN120','ADAPTIVE')}
    for r in submission['rows']:
        for label,sc in r['scores'].items(): counts[mapping[str(r['window'])][label]][str(sc)] +=1
    result={**summary,'reveal':'AFTER_COMPLETED_BLIND_SCORES_ONLY',
            'arm_counts':{arm:dict(n) for arm,n in counts.items()},
            'mean_score_excluding_uncertain':{
                arm:(round(sum(int(k)*v for k,v in c.items() if k!='?')/sum(v for k,v in c.items() if k!='?'),4)
                     if any(k!='?' for k in c) else None)
                for arm,c in counts.items()},
            'promotion':'NOT_AUTHORIZED_WITHOUT_REPEATED_MATCHED_ALL_IN_SPEED_AND_SEMANTIC_ADJUDICATION'}
    return result


def main(argv=None):
    p=argparse.ArgumentParser(description='Offline blind score validation; no LLM/network')
    p.add_argument('command',choices=('prepare','validate','unblind'))
    p.add_argument('--blind',required=True,type=Path)
    p.add_argument('--scores',required=True,type=Path)
    p.add_argument('--key',type=Path)
    p.add_argument('--out',type=Path)
    p.add_argument('--expected-blind-sha',help='Owner-pinned SHA256 for exact blinded 90-ID sheet (required for validate/unblind)')
    p.add_argument('--expected-key-sha',help='PRIVATELY precommitted canonical SHA256 of the exact owner key (required only for unblind; never publish this)')
    a=p.parse_args(argv)
    try:
        blind=_load(a.blind)
        blind_receipt=validate_blind(blind)
        if a.command!='prepare':
            if not a.expected_blind_sha:raise ReviewError('OWNER_PINNED_BLIND_SHA_REQUIRED')
            if a.expected_blind_sha!=blind_receipt['blind_sha256']:
                raise ReviewError('OWNER_PINNED_BLIND_SHA_MISMATCH')
        if a.command=='prepare':_save_new(a.scores,make_blank(blind)); report={'status':'BLANK_CREATED','entries':270}
        elif a.command=='validate': report=evaluate(blind,_load(a.scores))
        else:
            if a.key is None:raise ReviewError('OWNER_KEY_REQUIRED_AFTER_BLIND_REVIEW')
            report=unblind(blind,_load(a.scores),_load(a.key),expected_key_sha=a.expected_key_sha)
        if a.command!='prepare' and a.out: _save_new(a.out,report)
        print(json.dumps(report,ensure_ascii=False,sort_keys=True))
        return 0
    except (ReviewError, FileExistsError, FileNotFoundError, OSError) as e:
        error=(str(e) if isinstance(e,ReviewError) else 'FILE_IO_ERROR')
        print(json.dumps({'status':'BLOCKED','error_code':error},sort_keys=True));return 2

if __name__=='__main__':raise SystemExit(main())
