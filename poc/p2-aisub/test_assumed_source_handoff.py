"""Synthetic assumed-English-source handoff, without Brain search or live API."""
import hashlib
import json
from dataclasses import replace
import unittest

from assumed_source_handoff import (
    AssumedEnglishSubtitle, translate_supplied_to_feed,
)
from lan_revision_feed import SessionRevisionFeed
from lean120_api import ModelProfile

MEDIA="media."+"a"*64
OTHER="media."+"b"*64
SID="synthetic_tv_session_0001"
KEY=b"offline-paired-subtitle-secret-key-32"
PROFILE=ModelProfile("gemini","gemini-3.8-flash","medium")


def synthetic_srt(n=245):
    return ("\n\n".join(
        f"{i}\n00:{(i-1)//60:02d}:{(i-1)%60:02d},000 --> "
        f"00:{(i-1)//60:02d}:{(i-1)%60:02d},850\nEnglish synthetic {i}"
        for i in range(1,n+1)
    )+"\n").encode("utf8")


def fake_transport(url,headers,body,timeout):
    req=json.loads(body)
    target=json.loads(req["contents"][0]["parts"][0]["text"])["target"]
    return {"candidates":[{"finishReason":"STOP",
        "content":{"parts":[{"text":json.dumps({
            "translations":[{"id":x["id"],"vi":f"Câu thử {x['id']}"} for x in target]
        },ensure_ascii=False)}]}}]}


class AssumedSourceHandoffTests(unittest.TestCase):
    def setUp(self):
        self.handoff=AssumedEnglishSubtitle.from_supplied(
            media_key=MEDIA,fmt="srt",source_bytes=synthetic_srt())
        self.feed=SessionRevisionFeed(
            session_id=SID,media_key=MEDIA,
            source_sha256=self.handoff.source_sha256,pairing_secret=KEY)

    def test_explicit_supplied_source_lean120_without_brain_search(self):
        self.assertEqual(self.handoff.source_status,"ASSUMED_MATCHED_EN_TIMED_TEXT")
        self.assertEqual(self.handoff.cue_count,245)
        self.assertEqual(self.handoff.source_sha256,hashlib.sha256(self.handoff.source_bytes).hexdigest())
        res=translate_supplied_to_feed(
            self.handoff,PROFILE,feed=self.feed,glossary={},
            api_key="synthetic",transport=fake_transport)
        self.assertEqual([x.translated_count for x in res],[120,240,245])
        wire=json.loads(self.feed.latest())
        self.assertEqual(wire["translated_count"],245)
        self.assertEqual(wire["version"],3)
        self.assertEqual(wire["media_key"],MEDIA)
        self.assertEqual(wire["source_sha256"],self.handoff.source_sha256)

    def test_media_hash_timing_and_format_preflight_before_any_provider(self):
        called=[]
        def unexpected(*args):
            called.append(1)
            raise AssertionError("PROVIDER_MUST_NOT_BE_CALLED")
        for bad in [
            replace(self.handoff,media_key=OTHER),
            replace(self.handoff,source_sha256="f"*64),
            replace(self.handoff,cue_count=244),
            replace(self.handoff,source_bytes=synthetic_srt(1)),
            replace(self.handoff,source_status="VERIFIED_BY_BRAIN"),
        ]:
            with self.subTest(bad=bad),self.assertRaises(ValueError):
                translate_supplied_to_feed(bad,PROFILE,feed=self.feed,
                    glossary={},api_key="synthetic",transport=unexpected)
        self.assertEqual(called,[])

    def test_invalid_source_rejected_without_claiming_language_verification(self):
        for raw,fmt in [
            (b"\xff","srt"),(b"not timed text","srt"),(b"WEBVTT\n\n","vtt"),
            (synthetic_srt(1),"ass"),(b"","srt"),(b"x"*(256*1024+1),"srt")
        ]:
            with self.subTest(fmt=fmt,sz=len(raw)),self.assertRaises(ValueError):
                AssumedEnglishSubtitle.from_supplied(media_key=MEDIA,fmt=fmt,source_bytes=raw)
        with self.assertRaises(ValueError):
            AssumedEnglishSubtitle.from_supplied(media_key="wrong",fmt="srt",source_bytes=synthetic_srt(1))


if __name__=="__main__":unittest.main()
