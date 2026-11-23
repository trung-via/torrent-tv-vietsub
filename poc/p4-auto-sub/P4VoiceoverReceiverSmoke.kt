// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

/** Python-generated HMAC fixture for Ngọc Linh. Pure Kotlin/JVM: no TV output. */
fun main() {
    val sid = "synthetic_tv_session_0001"
    val media = "media." + "a".repeat(64)
    val source = "b".repeat(64)
    val secret = "synthetic_test_pairing_secret_32b".toByteArray(Charsets.UTF_8)
    val offer = P4VoiceoverOffer(
        "TTV-P4-VOICEOVER-OFFER-V1", sid, media, source, 1,
        "ngoc_linh_v3turbo_onnx", 1, 0, 1500,
        "c".repeat(64), "d".repeat(64), 48000, 800,
        "9baeca55347c14d4d9d150ab2a1f76c0fa8b256cfc26d15134f883022c8d7459",
    )
    val r = P4VoiceoverReceiver(sid, media, source, secret)
    var applied = 0
    val apply = { _: P4VoiceoverOffer -> applied++; true }
    check(r.receive(offer, sid, media, "OFF", "VLC", apply) ==
        "P4_VOICE_DEFERRED_USER_CHOICE")
    check(r.receive(offer, sid, media, "VOICE", "OTHER", apply) ==
        "P4_VOICE_UNSUPPORTED_ENGINE")
    check(applied == 0)
    check(r.receive(offer, sid, media, "BOTH", "VLC", apply) ==
        "P4_VOICE_QUEUED_NOT_AUDIBLE_PROOF")
    check(r.receive(offer, sid, media, "BOTH", "VLC", apply) ==
        "P4_VOICE_DUPLICATE")
    check(applied == 1)
    fun rejects(o: P4VoiceoverOffer, activeSession: String=sid, activeMedia: String=media) {
        try {
            r.receive(o, activeSession, activeMedia, "VOICE", "VLC", apply)
            error("invalid voice offer accepted")
        } catch (_: IllegalArgumentException) {}
    }
    rejects(offer.copy(startMs=1))
    rejects(offer.copy(wavSha256="f".repeat(64)))
    rejects(offer, activeSession="different_tv_session_0001")
    rejects(offer, activeMedia="media." + "f".repeat(64))
    rejects(offer.copy(mediaKey="media." + "f".repeat(64)))
    check(applied == 1)
    try {
        r.resetForSeek("wrong", media)
        error("foreign seek accepted")
    } catch (_: IllegalArgumentException) {}
    r.resetForSeek(sid, media)
    check(r.receive(offer, sid, media, "VOICE", "VLC", { false }) ==
        "P4_VOICE_NOT_QUEUED")
    check(r.receive(offer, sid, media, "VOICE", "VLC", apply) ==
        "P4_VOICE_QUEUED_NOT_AUDIBLE_PROOF")
    r.close()
    println("P4_VOICEOVER_NATIVE_HMAC_AND_SESSION_PASS_NOT_TV_AUDIO")
}
