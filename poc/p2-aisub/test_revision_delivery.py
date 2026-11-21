"""Synthetic P2 API→revision→G2 offer tests. Never contacts media, TV or cloud."""
from __future__ import annotations

from dataclasses import replace
import hashlib
import json
import unittest

from cue_pipeline import parse_cues
from progressive_handoff import ProgressiveSubtitleSession
from revision_delivery import PairedSubtitleReceiver, sign_revision
from lean120_api import ModelProfile, translate_all

SID = "synthetic_tv_session_0001"
A = "media." + "a" * 64
B = "media." + "b" * 64
SECRET = b"synthetic_test_pairing_secret_32b"
WRONG_SECRET = b"other_synthetic_pairing_secret"
PROFILE = ModelProfile("gemini", "gemini-3.8-flash", "medium")


def srt(count: int) -> bytes:
    return ("\n\n".join(
        f"{i}\n00:{(i-1)//60:02d}:{(i-1)%60:02d},000 --> "
        f"00:{(i-1)//60:02d}:{(i-1)%60:02d},850\nFictional source {i}."
        for i in range(1, count+1)
    )+"\n").encode("utf8")


def fake_api(url, headers, body, timeout):
    req=json.loads(body.decode("utf-8"))
    target=json.loads(req["contents"][0]["parts"][0]["text"])["target"]
    rows=[{"id":r["id"],"vi":f"Câu dịch thử {r['id']}"} for r in target]
    return {"candidates":[{"finishReason":"STOP",
             "content":{"parts":[{"text":json.dumps({"translations":rows},ensure_ascii=False)}]}}]}


class P4RevisionDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.source=srt(245)
        self.job=ProgressiveSubtitleSession(self.source,"srt",A)
        self.receiver=PairedSubtitleReceiver(session_id=SID,media_key=A,
                        source_sha256=self.job.source_sha256,pairing_secret=SECRET)
        self.applied=[]

    def callback(self,payload,fmt):
        self.applied.append((payload,fmt))
        return True

    def apply(self,offer,*,choice="ON",engine="VLC",session=SID,media=A,callback=None):
        return self.receiver.receive(
            offer,active_session=session,active_media_key=media,
            subtitles_choice=choice,engine=engine,
            on_g2_apply=self.callback if callback is None else callback
        )

    def revisions(self):
        return translate_all(self.source,"srt",A,PROFILE,
            glossary={"name":"tên nhân vật"},api_key="synthetic",
            transport=fake_api)

    def test_full_chain_api_to_cumulative_offers_no_per_batch_picker(self):
        revisions=self.revisions()
        self.assertEqual([x.translated_count for x in revisions],[120,240,245])
        results=[self.apply(sign_revision(x,SID,SECRET)) for x in revisions]
        self.assertEqual(results,["APPLIED_TO_G2"]*3)
        self.assertEqual(self.receiver.last_version,3)
        self.assertEqual(len(self.applied),3)
        self.assertEqual([len(parse_cues(b,"srt")) for b,_ in self.applied],[120,240,245])
        self.assertEqual(parse_cues(self.applied[1][0],"srt")[130].text,"Câu dịch thử 131")

    def test_off_other_and_wrong_engine_must_not_apply(self):
        r1,r2,r3=self.revisions()
        first=sign_revision(r1,SID,SECRET)
        second=sign_revision(r2,SID,SECRET)
        self.assertEqual(self.apply(first,choice="OFF"),"DEFERRED_USER_SUBTITLE_CHOICE")
        self.assertEqual(self.apply(first,choice="OTHER"),"DEFERRED_USER_SUBTITLE_CHOICE")
        self.assertEqual(self.apply(first,engine="Media3"),"DEFERRED_UNSUPPORTED_ENGINE")
        self.assertEqual(self.receiver.last_version,0)
        self.assertEqual(self.applied,[])
        # Later ON may apply the latest *cumulative* revision, not require manual v1 import.
        self.assertEqual(self.apply(second),"APPLIED_TO_G2")
        self.assertEqual(self.receiver.last_version,2)
        self.assertEqual(len(self.applied),1)
        self.assertEqual(len(parse_cues(self.applied[0][0],"srt")),240)

    def test_identical_replayed_offer_is_noop_and_prior_version_fails(self):
        r1,r2,_=self.revisions()
        a,b=(sign_revision(x,SID,SECRET) for x in (r1,r2))
        self.assertEqual(self.apply(a),"APPLIED_TO_G2")
        self.assertEqual(self.apply(a),"DUPLICATE_NOOP")
        self.assertEqual(self.apply(b),"APPLIED_TO_G2")
        with self.assertRaisesRegex(ValueError,"P4_STALE_REVISION"):
            self.apply(a)
        self.assertEqual(len(self.applied),2)

    def test_different_media_or_active_session_blocks_callback(self):
        offer=sign_revision(self.revisions()[0],SID,SECRET)
        for kw in [{"session":"other_session_0123456789"},
                   {"media":B}]:
            with self.subTest(kw=kw),self.assertRaisesRegex(ValueError,"P4_SESSION_OR_MEDIA_MISMATCH"):
                self.apply(offer,**kw)
        other_offer=replace(offer,media_key=B)
        with self.assertRaises(ValueError):self.apply(other_offer)
        other_session_offer=sign_revision(self.revisions()[0],"other_session_0123456789",SECRET)
        with self.assertRaises(ValueError):self.apply(other_session_offer)
        self.assertEqual(self.applied,[])

    def test_hmac_rejects_tamper_or_wrong_secret(self):
        offer=sign_revision(self.revisions()[0],SID,SECRET)
        changes=[
            replace(offer,version=2),
            replace(offer,translated_count=119),
            replace(offer,last_end_ms=1234),
            replace(offer,signature="0"*64),
        ]
        # Fields that are also structurally invalid must fail closed before HMAC.
        for bad in changes:
            with self.subTest(bad=bad.version),self.assertRaises(ValueError):
                self.apply(bad)
        wrong=sign_revision(self.revisions()[0],SID,WRONG_SECRET)
        with self.assertRaisesRegex(ValueError,"P4_AUTHENTICATION_FAILED"):
            self.apply(wrong)
        self.assertEqual(self.applied,[])

    def test_reject_invalid_content_or_mismatched_sha(self):
        offer=sign_revision(self.revisions()[0],SID,SECRET)
        wrong_payload=replace(offer,payload=offer.payload+b"tampered")
        with self.assertRaisesRegex(ValueError,"P4_PAYLOAD_HASH_MISMATCH"):
            self.apply(wrong_payload)
        invalid=replace(offer,payload_sha256="0"*64)
        with self.assertRaises(ValueError):
            self.apply(invalid)
        self.assertEqual(self.applied,[])

    def test_retry_after_g2_apply_failure_does_not_advance_cursor(self):
        offer=sign_revision(self.revisions()[0],SID,SECRET)
        def fail(*args):return False
        self.assertEqual(self.apply(offer,callback=fail),"G2_APPLY_FAILED_RETAIN_LAST_VALID")
        self.assertEqual(self.receiver.last_version,0)
        self.assertEqual(self.apply(offer),"APPLIED_TO_G2")
        self.assertEqual(self.receiver.last_version,1)

    def test_invalid_pairing_key_or_session_id(self):
        rev=self.revisions()[0]
        for key in [b"",b"short",None]:
            with self.subTest(key=key),self.assertRaises(ValueError):
                sign_revision(rev,SID,key)
        with self.assertRaises(ValueError):
            sign_revision(rev,"invalid",SECRET)
        with self.assertRaises(ValueError):
            PairedSubtitleReceiver(session_id="invalid",media_key=A,
                source_sha256=self.job.source_sha256,pairing_secret=SECRET)
        self.assertEqual(self.applied,[])

    def test_vtt_revisions_roundtrip_and_metadata(self):
        raw=(b"WEBVTT\n\nclip-1\n00:00:01.000 --> 00:00:02.400 align:start\nHello\n"
             b"\nclip-2\n00:00:04.000 --> 00:00:05.400\nGoodbye\n")
        session=ProgressiveSubtitleSession(raw,"vtt",A,max_cues=1)
        w=session.next_window()
        r1=session.commit(w,{1:"Xin chào"},expected_version=0,
                           source_sha256=session.source_sha256,media_key=A)
        w=session.next_window()
        r2=session.commit(w,{2:"Tạm biệt"},expected_version=1,
                           source_sha256=session.source_sha256,media_key=A)
        receiver=PairedSubtitleReceiver(session_id=SID,media_key=A,
                      source_sha256=session.source_sha256,pairing_secret=SECRET)
        observed=[]
        def consume(raw,fmt):
            observed.append((raw,fmt));return True
        for rev in [r1,r2]:
            out=receiver.receive(sign_revision(rev,SID,SECRET),
                active_session=SID,active_media_key=A,subtitles_choice="ON",
                engine="VLC",on_g2_apply=consume)
            self.assertEqual(out,"APPLIED_TO_G2")
        cues=parse_cues(observed[-1][0],"vtt")
        self.assertEqual(cues[0].identifier,"clip-1")
        self.assertEqual(cues[0].settings," align:start")
        self.assertEqual(cues[1].text,"Tạm biệt")
        self.assertEqual(receiver.last_version,2)


if __name__=="__main__":
    unittest.main()
