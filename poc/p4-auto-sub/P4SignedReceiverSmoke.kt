// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

/**
 * Cross-language fixtures signed with Python P2 revision_delivery.py:
 * json.dumps(..., sort_keys=True, separators=(",", ":")) + HMAC-SHA256.
 * No Android, provider, network, TorrServer or user subtitles involved.
 */
fun main() {
    val session = "synthetic_tv_session_0001"
    val media = "media." + "a".repeat(64)
    val src = "b".repeat(64)
    val secret = "synthetic_test_pairing_secret_32b".toByteArray(Charsets.UTF_8)
    val original = "1\n00:00:00,000 --> 00:00:00,850\nCâu thử 1\n\n" +
        "2\n00:00:01,000 --> 00:00:01,850\nCâu thử 2\n"
    val extended = original + "\n3\n00:00:02,000 --> 00:00:02,850\nCâu thử 3\n"
    val first = P4SubtitleOffer(
        session, media, src, 1, "srt", 2, 4, 1850,
        "0ed944dd0997dac780e98908ca34cd2f21c1fe229717e6c9155a61549616fbd4",
        original.toByteArray(Charsets.UTF_8),
        "7ed1113e37ec29521795d80c64bf0076498a373eff385b401e1f01923f03c4b7",
    )
    val second = P4SubtitleOffer(
        session, media, src, 2, "srt", 3, 4, 2850,
        "01e492037f52266fb7ec4e718c0a7773b7fd25abcf4fba7fcd48d6a9dd48342a",
        extended.toByteArray(Charsets.UTF_8),
        "03a1a422b8d9c4bd8bfad08d6f124186765874dfdc9d07a6400f6a6eb5391582",
    )
    val receiver = P4SignedReceiver(session, media, src, secret)
    var calls = 0
    fun accept(payload: ByteArray, fmt: String): Boolean { check(payload.isNotEmpty() && fmt in setOf("srt", "vtt")); calls++; return true }
    check(receiver.receive(first, session, media, "ON", "VLC", ::accept) == "G2_PENDING_FIRST_FRAME")
    check(receiver.pendingVersionForTest() == 1 && receiver.lastAppliedForTest() == 0)
    check(receiver.receive(first, session, media, "ON", "VLC", ::accept) == "G2_PENDING_DUPLICATE_NOOP")
    check(receiver.acknowledgeFirstFrame(session, media, "ON", "VLC",
        1, first.payloadSha256) == "APPLIED_TO_G2")
    check(receiver.receive(first, session, media, "ON", "VLC", ::accept) == "DUPLICATE_NOOP")
    check(calls == 1)
    check(receiver.receive(second, session, media, "ON", "VLC", ::accept) == "G2_PENDING_FIRST_FRAME")
    check(receiver.lastAppliedForTest() == 1)
    check(receiver.acknowledgeFirstFrame(session, media, "ON", "VLC",
        2, second.payloadSha256) == "APPLIED_TO_G2")
    check(receiver.lastAppliedForTest() == 2)
    check(calls == 2)
    try {
        receiver.receive(first, session, media, "ON", "VLC", ::accept)
        error("replay accepted")
    } catch (e: IllegalArgumentException) { check(e.message == "P4_STALE_REVISION") }
    check(calls == 2)

    val fresh = P4SignedReceiver(session, media, src, secret)
    check(fresh.receive(first, session, media, "OFF", "VLC", ::accept) == "DEFERRED_USER_SUBTITLE_CHOICE")
    check(fresh.receive(first, session, media, "OTHER", "VLC", ::accept) == "DEFERRED_USER_SUBTITLE_CHOICE")
    check(fresh.receive(first, session, media, "ON", "Media3", ::accept) == "DEFERRED_UNSUPPORTED_ENGINE")
    check(fresh.lastAppliedForTest() == 0)
    check(calls == 2)
    check(fresh.receive(second, session, media, "ON", "VLC", ::accept) == "G2_PENDING_FIRST_FRAME")
    check(fresh.lastAppliedForTest() == 0)
    check(fresh.acknowledgeFirstFrame(session, media, "ON", "VLC",
        2, second.payloadSha256) == "APPLIED_TO_G2")
    check(fresh.lastAppliedForTest() == 2)
    check(calls == 3)

    val retry = P4SignedReceiver(session, media, src, secret)
    check(retry.receive(first, session, media, "ON", "VLC", { _, _ -> false }) ==
        "G2_APPLY_FAILED_RETAIN_LAST_VALID")
    check(retry.lastAppliedForTest() == 0)
    check(retry.receive(first, session, media, "ON", "VLC", ::accept) == "G2_PENDING_FIRST_FRAME")
    check(retry.lastAppliedForTest() == 0)
    check(retry.abortPending(1, first.payloadSha256))
    check(retry.lastAppliedForTest() == 0)
    check(retry.receive(first, session, media, "ON", "VLC", ::accept) == "G2_PENDING_FIRST_FRAME")
    try {
        retry.acknowledgeFirstFrame(session, media, "OFF", "VLC", 1, first.payloadSha256)
        error("OFF was allowed to acknowledge automatic subtitles")
    } catch (e: IllegalArgumentException) { check(e.message == "P4_FIRST_FRAME_SCOPE_MISMATCH") }
    check(retry.lastAppliedForTest() == 0)
    check(retry.receive(first, session, media, "ON", "VLC", ::accept) == "G2_PENDING_FIRST_FRAME")
    check(retry.acknowledgeFirstFrame(session, media, "ON", "VLC",
        1, first.payloadSha256) == "APPLIED_TO_G2")
    check(retry.lastAppliedForTest() == 1)

    fun mustReject(offer: P4SubtitleOffer, activeSession: String = session, activeMedia: String = media) {
        try {
            fresh.receive(offer, activeSession, activeMedia, "ON", "VLC", ::accept)
            error("invalid offer accepted")
        } catch (_: IllegalArgumentException) { }
    }
    mustReject(second.copy(payload=second.payload + byteArrayOf(1)))
    mustReject(second.copy(signature = "0".repeat(64)))
    mustReject(second.copy(lastEndMs = 3850))
    mustReject(second.copy(translatedCount = 4))
    mustReject(second.copy(mediaKey = "media." + "c".repeat(64)))
    mustReject(second, activeMedia="media." + "c".repeat(64))
    mustReject(second, activeSession="different_tv_session_0001")
    val goodVtt = P4SubtitleOffer(
        session, media, src, 1, "vtt", 2, 4, 1850,
        "a15b8d3bd0e4f9cb53a09b0f49dad09cacb052aba3fddd26e73175476503b374",
        ("WEBVTT\n\nscene-one\n00:00:00.000 --> 00:00:00.850 align:start\nCâu thử 1\n\n" +
         "00:00:01.000 --> 00:00:01.850\nCâu thử 2\n").toByteArray(Charsets.UTF_8),
        "9a4fc2e878bfbef91f8b7693c9e289ce75a58910235143e5eb38c2491aff5422",
    )
    val vttReceiver = P4SignedReceiver(session, media, src, secret)
    check(vttReceiver.receive(goodVtt, session, media, "ON", "VLC", ::accept) == "G2_PENDING_FIRST_FRAME")
    check(vttReceiver.acknowledgeFirstFrame(session, media, "ON", "VLC",
        1, goodVtt.payloadSha256) == "APPLIED_TO_G2")
    check(calls == 7)

    // A new Activity after process restart must reject old valid HMAC offers.
    val resumed = P4SignedReceiver(
        session, media, src, secret,
        acceptedVersion=2, acceptedDigest=second.payloadSha256)
    check(resumed.receive(second, session, media, "ON", "VLC", ::accept) == "DUPLICATE_NOOP")
    try {
        resumed.receive(first, session, media, "ON", "VLC", ::accept)
        error("a stale valid signed revision was replayed after restart")
    } catch (e: IllegalArgumentException) { check(e.message == "P4_STALE_REVISION") }

    // Failure to durably persist the first-frame ACK must not advance the cursor.
    val noPersistence = P4SignedReceiver(
        session, media, src, secret,
        onFirstFrameAccepted={ _, _ -> false })
    check(noPersistence.receive(first, session, media, "ON", "VLC", ::accept) ==
        "G2_PENDING_FIRST_FRAME")
    check(noPersistence.acknowledgeFirstFrame(session, media, "ON", "VLC", 1,
        first.payloadSha256) == "P4_PERSISTENCE_FAILED_RETAIN_LAST_VALID")
    check(noPersistence.lastAppliedForTest() == 0)
    check(noPersistence.receive(first, session, media, "ON", "VLC", ::accept) ==
        "G2_PENDING_FIRST_FRAME")
    check(noPersistence.abortPending(1, first.payloadSha256))
    try {
        P4SignedReceiver(session, media, src, secret,
            acceptedVersion=1, acceptedDigest=null)
        error("corrupted persisted cursor accepted")
    } catch (e: IllegalArgumentException) { check(e.message == "P4_STORED_LEDGER_INVALID") }

    println("P4_NATIVE_SIGNED_RECEIVER_SYNTHETIC_PASS (Kotlin/JVM, Python-HMAC cross-language)")
}
