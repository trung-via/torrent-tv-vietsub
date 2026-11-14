"""Synthetic PC↔TV activation: no Brain search, network bind, or provider call."""
from __future__ import annotations
import hashlib
import hmac
import json
import ssl
from dataclasses import replace
import unittest
from unittest import mock

from assumed_source_handoff import AssumedEnglishSubtitle
from paired_activation import (
    PairedActivation,activation_request_mac,activation_response_mac,
    create_paired_server,derive_session_secret,make_paired_handler,
)
from lan_revision_feed import SessionRevisionFeed

MEDIA="media."+"a"*64
OTHER="media."+"b"*64
MASTER=b"synthetic-pairing-device-key-32x"
assert len(MASTER)==32


def src():
    return b"1\n00:00:01,000 --> 00:00:01,850\nSynthetic English\n"


class PCActivationTests(unittest.TestCase):
    def setUp(self):
        self.handoff=AssumedEnglishSubtitle.from_supplied(
            media_key=MEDIA,fmt="srt",source_bytes=src())
        self.queued=[]
        self.controller=PairedActivation(
            device_secret=MASTER,supplied={MEDIA:self.handoff},
            on_activate=lambda feed,source:self.queued.append((feed,source)),
        )

    def request(self,media=MEDIA,nonce="1"*32,secret=MASTER):
        return {
            "schema":"TTV-P4-ACTIVATE-V1","media_key":media,
            "nonce":nonce,"auth":activation_request_mac(secret,media,nonce)
        }

    def test_one_device_pairing_authorizes_exact_film_only_and_derives_secret(self):
        response=self.controller.activate(self.request())
        self.assertEqual(response["schema"],"TTV-P4-ACTIVATED-V1")
        self.assertEqual(response["media_key"],MEDIA)
        self.assertEqual(response["source_sha256"],self.handoff.source_sha256)
        self.assertEqual(response["nonce"],"1"*32)
        self.assertEqual(response["auth"],activation_response_mac(
            MASTER,MEDIA,"1"*32,response["session_id"],self.handoff.source_sha256))
        self.assertEqual(len(self.queued),1)
        feed,source=self.queued[0]
        self.assertIs(self.controller.feed_for(response["session_id"]),feed)
        self.assertIs(source,self.handoff)
        session_key=derive_session_secret(
            MASTER,response["session_id"],MEDIA,self.handoff.source_sha256)
        self.assertEqual(len(session_key),32)
        self.assertIsInstance(feed,SessionRevisionFeed)
        self.assertNotEqual(session_key,MASTER)

    def test_wrong_film_or_replay_or_tamper_rejected(self):
        bad=self.request()
        bad["auth"]="0"*64
        with self.assertRaisesRegex(ValueError,"AUTH_INVALID"):
            self.controller.activate(bad)
        with self.assertRaisesRegex(ValueError,"SOURCE_MISSING"):
            self.controller.activate(self.request(media=OTHER))
        response=self.controller.activate(self.request())
        with self.assertRaisesRegex(ValueError,"REPLAY"):
            self.controller.activate(self.request())
        invalid=self.request(nonce="3"*32)
        invalid["media_key"]=OTHER
        with self.assertRaisesRegex(ValueError,"AUTH_INVALID"):
            self.controller.activate(invalid)
        self.assertEqual(len(self.queued),1)

    def test_dev_mock_binds_first_authenticated_media_only_and_never_before_auth(self):
        calls=[]
        def fixture(media):
            calls.append(media)
            return AssumedEnglishSubtitle.from_supplied(
                media_key=media,fmt="srt",source_bytes=src())
        paired=PairedActivation(
            device_secret=MASTER,supplied={},
            authenticated_mock_source_factory=fixture)
        wrong=self.request(media=MEDIA,nonce="5"*32,secret=b"x"*32)
        with self.assertRaisesRegex(ValueError,"AUTH_INVALID"):
            paired.activate(wrong)
        self.assertEqual(calls,[])
        first=paired.activate(self.request(media=MEDIA,nonce="6"*32))
        self.assertEqual(first["media_key"],MEDIA)
        self.assertEqual(calls,[MEDIA])
        self.assertIsNotNone(paired.feed_for(first["session_id"]))
        # The first media remains locked for the whole process, even if
        # the second request carries a valid pairing HMAC.
        with self.assertRaisesRegex(ValueError,"P4_MOCK_ONE_MEDIA_ONLY"):
            paired.activate(self.request(media=OTHER,nonce="7"*32))
        self.assertEqual(calls,[MEDIA])
        with self.assertRaisesRegex(ValueError,"REPLAY"):
            paired.activate(self.request(media=MEDIA,nonce="6"*32))
        second=paired.activate(self.request(media=MEDIA,nonce="8"*32))
        self.assertEqual(second["media_key"],MEDIA)
        self.assertEqual(calls,[MEDIA])
        self.assertNotEqual(first["session_id"],second["session_id"])

    def test_dev_mock_factory_cannot_override_explicit_source(self):
        with self.assertRaisesRegex(ValueError,"MOCK_SOURCE_FACTORY_SCOPE_INVALID"):
            PairedActivation(
                device_secret=MASTER,supplied={MEDIA:self.handoff},
                authenticated_mock_source_factory=lambda _:self.handoff)
        with self.assertRaisesRegex(ValueError,"MOCK_SOURCE_FACTORY_SCOPE_INVALID"):
            PairedActivation(
                device_secret=MASTER,supplied={},
                authenticated_mock_source_factory="not callable")
        paired=PairedActivation(
            device_secret=MASTER,supplied={},
            authenticated_mock_source_factory=lambda _:self.handoff)
        # The returned handoff must be bound to authenticated media, not
        # an arbitrary fixture or another profile.
        with self.assertRaisesRegex(ValueError,"P4_MOCK_FACTORY_MEDIA_MISMATCH"):
            paired.activate(self.request(media=OTHER,nonce="9"*32))

    def test_assumed_english_source_activation_to_lean120_signed_feed(self):
        from assumed_source_handoff import translate_supplied_to_feed
        from lean120_api import ModelProfile
        provider_calls=[]
        def fake_provider(url,headers,body,timeout):
            req=json.loads(body)
            target=json.loads(req["contents"][0]["parts"][0]["text"])["target"]
            provider_calls.append([x["id"] for x in target])
            return {"candidates":[{"finishReason":"STOP",
                "content":{"parts":[{"text":json.dumps({
                    "translations":[{"id":x["id"],"vi":"Câu thử nghiệm"} for x in target]
                })}]}}]}
        def start_translation(feed,source):
            translate_supplied_to_feed(
                source,ModelProfile("gemini","gemini-3.8-flash","medium"),
                feed=feed,glossary={},api_key="synthetic",transport=fake_provider)
        paired=PairedActivation(
            device_secret=MASTER,supplied={MEDIA:self.handoff},
            on_activate=start_translation)
        reply=paired.activate(self.request(nonce="4"*32))
        self.assertEqual(provider_calls,[[1]])
        feed=paired.feed_for(reply["session_id"])
        wire=json.loads(feed.latest())
        self.assertEqual(wire["version"],1)
        self.assertEqual(wire["translated_count"],1)
        self.assertEqual(wire["media_key"],MEDIA)
        self.assertEqual(wire["source_sha256"],self.handoff.source_sha256)
        key=derive_session_secret(
            MASTER,reply["session_id"],MEDIA,self.handoff.source_sha256)
        nonce="5"*32
        tag=hmac.new(key,
            ("TTV-P4-LAN-READ-V1\n"+reply["session_id"]+"\n"+nonce).encode("ascii"),
            hashlib.sha256).hexdigest()
        self.assertTrue(feed.authorize_read(nonce,tag))
        self.assertFalse(feed.authorize_read(nonce,tag))

    def test_no_finder_or_server_or_paid_api_on_import(self):
        ctx=mock.Mock(
            protocol=ssl.PROTOCOL_TLS_SERVER,
            minimum_version=ssl.TLSVersion.TLSv1_2)
        with mock.patch("paired_activation.HTTPServer") as srv:
            plain_socket=srv.return_value.socket
            create_paired_server(self.controller,host="192.168.1.15",
                                 port=19009,tls_context=ctx)
            self.assertEqual(srv.call_args.args[0],("192.168.1.15",19009))
            ctx.wrap_socket.assert_called_once_with(plain_socket,server_side=True)
        for ip in ("0.0.0.0","8.8.8.8","localhost"):
            with self.subTest(ip=ip),self.assertRaises(ValueError):
                create_paired_server(self.controller,host=ip,port=19009,
                                     tls_context=ctx)
        with self.assertRaises(ValueError):
            create_paired_server(self.controller,host="192.168.1.15",
                                 port=80,tls_context=ctx)
        with self.assertRaisesRegex(ValueError,"TLS_CONTEXT_REQUIRED"):
            create_paired_server(self.controller,host="192.168.1.15",
                                 port=19009,tls_context=None)
        ctx.minimum_version=ssl.TLSVersion.TLSv1_1
        with self.assertRaisesRegex(ValueError,"TLS_CONTEXT_REQUIRED"):
            create_paired_server(self.controller,host="192.168.1.15",
                                 port=19009,tls_context=ctx)
        self.assertFalse(self.queued)

    def test_activation_http_contract_and_signed_reader(self):
        cls=make_paired_handler(self.controller)
        handler=object.__new__(cls)
        from io import BytesIO
        responses=[];headers=[];outputs=[]
        handler.send_response=lambda n:responses.append(n)
        handler.send_header=lambda k,v:headers.append((k,v))
        handler.end_headers=lambda:None
        handler.send_error=lambda n:responses.append(n)
        class Sink:
            def write(self,b):outputs.append(b)
        handler.wfile=Sink()
        r=json.dumps(self.request()).encode("ascii")
        handler.path="/p4/activate"
        handler.headers={"Content-Type":"application/json","Content-Length":str(len(r))}
        handler.rfile=BytesIO(r)
        handler.do_POST()
        self.assertEqual(responses[-1],200)
        reply=json.loads(outputs[-1])
        sid=reply["session_id"]
        handler.path="/p4/revision/"+sid
        handler.headers={}
        handler.do_GET()
        self.assertEqual(responses[-1],401)
        nonce="2"*32
        secret=derive_session_secret(MASTER,sid,MEDIA,self.handoff.source_sha256)
        handler.headers={
            "X-P4-Nonce":nonce,
            "X-P4-Authorization":hmac.new(
                secret,("TTV-P4-LAN-READ-V1\n"+sid+"\n"+nonce).encode("ascii"),
                hashlib.sha256).hexdigest(),
        }
        handler.do_GET()
        self.assertEqual(responses[-1],204)
        handler.do_GET()
        self.assertEqual(responses[-1],401)


if __name__=="__main__":unittest.main()
