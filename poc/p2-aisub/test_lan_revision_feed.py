"""P4 LAN revision feed uses no WAN or live provider. Fully synthetic CI."""
import base64
from dataclasses import replace
import hashlib
import json
from unittest import TestCase, main, mock

from lan_revision_feed import (
    SessionRevisionFeed, create_server, make_handler, offer_wire, private_lan_ip,
    translate_into_feed,
)
from progressive_handoff import ProgressiveSubtitleSession
from revision_delivery import SignedSubtitleOffer, PairedSubtitleReceiver

SID="synthetic_tv_session_0001"
MEDIA="media." + "a"*64
OTHER="media." + "b"*64
SECRET=b"synthetic_private_pairing_key_32"


def source(n):
    return ("\n\n".join(
        f"{i}\n00:00:{i-1:02},000 --> 00:00:{i-1:02},850\nSynthetic cue {i}"
        for i in range(1,n+1)
    ) + "\n").encode("utf8")


def revision_pair():
    job=ProgressiveSubtitleSession(source(4),"srt",MEDIA,max_cues=2)
    def next_revision(version):
        window=job.next_window()
        return job.commit(
            window,{i:f"Phụ đề thử {i}" for i in window.ids},
            expected_version=version,source_sha256=job.source_sha256,media_key=MEDIA,
        )
    return job, next_revision(0), next_revision(1)


class SessionRevisionFeedTests(TestCase):
    def setUp(self):
        self.session,self.first,self.second=revision_pair()
        self.feed=SessionRevisionFeed(
            session_id=SID,media_key=MEDIA,
            source_sha256=self.session.source_sha256,pairing_secret=SECRET,
        )

    def test_publish_and_integrity_roundtrip_to_existing_verified_receiver(self):
        self.assertIsNone(self.feed.latest())
        self.assertEqual(self.feed.publish(self.first),"PUBLISHED")
        wire=self.feed.latest()
        data=json.loads(wire)
        self.assertEqual(data["schema"],"TTV-P4-LAN-REVISION-V1")
        self.assertEqual(data["session_id"],SID)
        self.assertEqual(data["version"],1)
        self.assertEqual(data["fmt"],"srt")
        self.assertEqual(base64.b64decode(data["payload_b64"],validate=True),self.first.payload)
        offer=SignedSubtitleOffer(
            session_id=data["session_id"],media_key=data["media_key"],
            source_sha256=data["source_sha256"],version=data["version"],
            fmt=data["fmt"],translated_count=data["translated_count"],
            total_count=data["total_count"],last_end_ms=data["last_end_ms"],
            payload_sha256=data["payload_sha256"],
            payload=base64.b64decode(data["payload_b64"],validate=True),
            signature=data["signature"],
        )
        receiver=PairedSubtitleReceiver(session_id=SID,media_key=MEDIA,
            source_sha256=self.session.source_sha256,pairing_secret=SECRET)
        called=[]
        self.assertEqual(receiver.receive(
            offer,active_session=SID,active_media_key=MEDIA,
            subtitles_choice="OFF",engine="VLC",
            on_g2_apply=lambda raw,fmt: called.append(raw) or True
        ),"DEFERRED_USER_SUBTITLE_CHOICE")
        self.assertFalse(called)
        self.assertEqual(receiver.receive(
            offer,active_session=SID,active_media_key=MEDIA,
            subtitles_choice="ON",engine="VLC",
            on_g2_apply=lambda raw,fmt: called.append(raw) or True
        ),"APPLIED_TO_G2")
        self.assertEqual(called,[self.first.payload])

    def test_monotonic_versions_and_duplicate_noop(self):
        self.assertEqual(self.feed.publish(self.first),"PUBLISHED")
        wire=self.feed.latest()
        self.assertEqual(self.feed.publish(self.first),"DUPLICATE_NOOP")
        self.assertEqual(self.feed.latest(),wire)
        self.assertEqual(self.feed.publish(self.second),"PUBLISHED")
        self.assertEqual(json.loads(self.feed.latest())["version"],2)
        with self.assertRaisesRegex(ValueError,"STALE_VERSION"):
            self.feed.publish(self.first)
        fake=replace(self.second,payload=b"fake",sha256=hashlib.sha256(b"fake").hexdigest())
        with self.assertRaises(ValueError):
            self.feed.publish(fake)
        self.assertEqual(json.loads(self.feed.latest())["version"],2)

    def test_wrong_media_source_and_pairing_rejected(self):
        with self.assertRaisesRegex(ValueError,"SOURCE_OR_MEDIA_MISMATCH"):
            self.feed.publish(replace(self.first,media_key=OTHER))
        with self.assertRaisesRegex(ValueError,"SOURCE_OR_MEDIA_MISMATCH"):
            self.feed.publish(replace(self.first,source_sha256="f"*64))
        with self.assertRaisesRegex(ValueError,"P4_SESSION_ID_INVALID"):
            SessionRevisionFeed(session_id="bad",media_key=MEDIA,
                source_sha256=self.session.source_sha256,pairing_secret=SECRET)
        with self.assertRaisesRegex(ValueError,"P4_SECRET_REQUIRED"):
            SessionRevisionFeed(session_id=SID,media_key=MEDIA,
                source_sha256=self.session.source_sha256,pairing_secret=b"short")

    def test_private_network_binding_only_and_never_bind_on_import(self):
        for ip in ("10.4.5.6","172.16.0.1","172.31.255.254","192.168.0.50"):
            self.assertEqual(private_lan_ip(ip),ip)
        for ip in ("127.0.0.1","0.0.0.0","169.254.1.2","8.8.8.8","172.32.0.1",
                   "localhost","192.168.0.1.evil.net","::1","192.168.1.256"):
            with self.subTest(ip=ip),self.assertRaises(ValueError):
                private_lan_ip(ip)
        with mock.patch("lan_revision_feed.HTTPServer") as http:
            create_server(self.feed,host="192.168.1.2",port=19009)
            self.assertEqual(http.call_args.args[0],("192.168.1.2",19009))
            self.assertTrue(callable(http.call_args.args[1]))
        with self.assertRaises(ValueError):
            create_server(self.feed,host="0.0.0.0",port=19009)
        with self.assertRaises(ValueError):
            create_server(self.feed,host="192.168.1.2",port=80)

    def test_api_batch_to_signed_feed_without_human_picker_or_network(self):
        from lean120_api import ModelProfile
        src = ("\n\n".join(
            f"{i}\n00:{(i-1)//60:02d}:{(i-1)%60:02d},000 --> "
            f"00:{(i-1)//60:02d}:{(i-1)%60:02d},850\nSynthetic {i}"
            for i in range(1,242)
        )+"\n").encode("utf8")
        job = ProgressiveSubtitleSession(src,"srt",MEDIA)
        feed = SessionRevisionFeed(session_id=SID,media_key=MEDIA,
                    source_sha256=job.source_sha256,pairing_secret=SECRET)
        calls=[]
        def fake_api(url,headers,body,timeout):
            req=json.loads(body)
            ids=[x["id"] for x in json.loads(
                req["contents"][0]["parts"][0]["text"])["target"]]
            calls.append(ids)
            rows=[{"id":i,"vi":f"Vietsub số {i}"} for i in ids]
            return {"candidates":[{"finishReason":"STOP","content":{"parts":[
                {"text":json.dumps({"translations":rows},ensure_ascii=False)}
            ]}}]}
        profile = ModelProfile.from_json({
            "provider":"gemini", "model":"gemini-3.8-flash",
            "thinking_level":"medium",
        })
        with self.assertRaisesRegex(ValueError,"P4_FEED_SOURCE_SHA_MISMATCH"):
            translate_into_feed(src+b"tamper","srt",MEDIA,profile,
                feed=feed,glossary={},api_key="synthetic",transport=fake_api)
        with self.assertRaisesRegex(ValueError,"P4_FEED_MEDIA_MISMATCH"):
            translate_into_feed(src,"srt",OTHER,profile,
                feed=feed,glossary={},api_key="synthetic",transport=fake_api)
        self.assertFalse(calls)
        revisions=translate_into_feed(src,"srt",MEDIA,profile,
            feed=feed,glossary={},api_key="synthetic",transport=fake_api)
        self.assertEqual([r.translated_count for r in revisions],[120,240,241])
        self.assertEqual([len(ids) for ids in calls],[120,120,1])
        wire=json.loads(feed.latest())
        self.assertEqual(wire["version"],3)
        self.assertEqual(wire["translated_count"],241)
        self.assertEqual(wire["payload_sha256"],revisions[-1].sha256)
        self.assertEqual(base64.b64decode(wire["payload_b64"]),revisions[-1].payload)

    def test_handler_fixed_endpoint_no_directory_and_readonly(self):
        Handler=make_handler(self.feed)
        handler=object.__new__(Handler)
        status=[]
        headers=[]
        payload=[]
        handler.send_response=lambda code: status.append(code)
        handler.send_header=lambda k,v: headers.append((k,v))
        handler.end_headers=lambda: None
        handler.send_error=lambda code: status.append(code)
        class DummyStream:
            def write(self, chunk):
                payload.append(chunk)
        handler.wfile=DummyStream()
        handler.path="/p4/revision/"+SID
        handler.do_GET()
        self.assertEqual(status,[204])
        self.assertEqual(payload,[])
        handler.path="/p4/revision/../etc/passwd"
        handler.do_GET()
        self.assertEqual(status[-1],404)
        handler.path="/p4/revision/"+SID
        self.feed.publish(self.first)
        handler.do_GET()
        self.assertEqual(status[-1],200)
        self.assertEqual(payload[-1],self.feed.latest())
        self.assertIn(("Cache-Control","no-store"),headers)
        handler.do_POST()
        self.assertEqual(status[-1],405)


if __name__=="__main__":main()
