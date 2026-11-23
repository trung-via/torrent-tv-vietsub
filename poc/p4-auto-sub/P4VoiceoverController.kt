// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * Activity-owned voice lane: existing P4 session → signed offers → pinned WAV
 * → AudioTrack. Network, SHA and PCM preparation run off the main thread.
 * No second Owner, service, listener, media stream, model or translation call.
 */
internal class P4VoiceoverController(
    private val host: String,
    private val port: Int,
    private val sid: String,
    private val mediaKey: String,
    sourceSha256: String,
    pairedSecret: ByteArray,
    private val certPin: String,
    private val onUnavailable: (String) -> Unit = {},
) {
    private val main = Handler(Looper.getMainLooper())
    private val secret = pairedSecret.clone()
    private val receiver = P4VoiceoverReceiver(sid, mediaKey, sourceSha256, secret)
    private val player = P4VoiceoverAudioTrack()
    private var generation = 0
    private var closed = false
    private var mode = "SUBS"
    private var cursor = 0
    private var inflight = false
    private var lastFetchAt = 0L
    private var lastPosition: Long? = null
    private var unavailable = false

    internal fun setMode(next: String) {
        require(next in setOf("SUBS", "VOICE", "BOTH")) { "P4_VOICE_MODE_INVALID" }
        if (closed || mode == next) return
        mode = next
        generation++
        inflight = false
        // Switching OFF narration must cut audio immediately. The committed
        // WAV cache remains on the PC and can be rebound to this film later.
        if (next == "SUBS") {
            player.reset()
        } else {
            cursor = 0 // Revisit only cues not yet expired on the live clock.
        }
    }

    /**
     * Must be called on PlayerActivity's main thread for THIS paired film.
     * Returns whether the narration is audible/playing at this tick (not an
     * actual SPDIF/soundbar acceptance receipt).
     */
    internal fun tick(
        activeSession: String, activeMedia: String, positionMs: Long,
        playing: Boolean, buffering: Boolean,
    ): Boolean {
        if (closed) return false
        if (activeSession != sid || activeMedia != mediaKey) {
            close() // Never leak A's prepared voiceover into B.
            return false
        }
        if (P4VoiceoverTimeline.discontinuity(lastPosition, positionMs)) {
            seeked(activeSession, activeMedia)
        }
        lastPosition = positionMs
        if (mode == "SUBS" || unavailable) {
            player.reset()
            return false
        }
        val speaking = player.tick(positionMs, playing, buffering)
        val now = SystemClock.uptimeMillis()
        if (!playing || buffering || inflight || now - lastFetchAt < 1800L) {
            return speaking
        }
        lastFetchAt = now
        inflight = true
        val token = generation
        val after = cursor
        Thread {
            val page = try {
                P4VoiceoverLanClient.listCues(host, port, sid, secret, certPin, after)
            } catch (exc: Exception) {
                main.post {
                    if (closed || generation != token) return@post
                    inflight = false
                    if (exc is P4LanSessionExpired ||
                        exc is P4LanAuthorizationRejected) {
                        unavailable = true
                        player.reset()
                        onUnavailable("P4_VOICE_OWNER_AUDIO_UNAVAILABLE")
                    }
                }
                return@Thread
            }
            main.post {
                if (closed || generation != token) return@post
                processPage(page, token, positionMs)
            }
        }.start()
        return speaking
    }

    private fun processPage(
        page: P4VoiceoverLanClient.Page, token: Int, sampledPosition: Long,
    ) {
        var previous = cursor
        try {
            if (page.offers.size > 32) {
                throw IllegalArgumentException("P4_VOICE_PAGE_TOO_LARGE")
            }
            for (offer in page.offers) {
                if (offer.cueNumber <= previous) {
                    throw IllegalArgumentException("P4_VOICE_CUE_ORDER_INVALID")
                }
                receiver.verify(offer, sid, mediaKey)
                previous = offer.cueNumber
                // A late title can have many already-spoken captions. Advance
                // only AFTER verifying their per-cue signatures.
                if (offer.endMs < sampledPosition - 250L) {
                    cursor = offer.cueNumber
                    continue
                }
                // Do not buffer an entire film in the TV's memory.
                if (offer.startMs > sampledPosition + 20_000L) break
                val selected = offer
                Thread {
                    val prepared = try {
                        val bytes = P4VoiceoverLanClient.wav(
                            host, port, sid, secret, certPin, selected)
                        P4VoiceoverAudioTrack.Prepared.fromWav(selected, bytes)
                    } catch (_: Exception) {
                        null
                    }
                    main.post {
                        if (closed || generation != token || mode == "SUBS" ||
                            unavailable) {
                            prepared?.close()
                            return@post
                        }
                        try {
                            if (prepared != null) {
                                val outcome = receiver.receive(
                                    selected, sid, mediaKey, mode, "VLC") {
                                    player.enqueue(prepared)
                                }
                                if (outcome == "P4_VOICE_QUEUED_NOT_AUDIBLE_PROOF" ||
                                    outcome == "P4_VOICE_DUPLICATE") {
                                    cursor = selected.cueNumber
                                } else if (outcome != "P4_VOICE_NOT_QUEUED") {
                                    prepared.close()
                                }
                            }
                        } catch (_: Exception) {
                            prepared?.close()
                        } finally {
                            inflight = false
                        }
                    }
                }.start()
                return
            }
        } catch (_: Exception) {
            // No trust is granted to a malformed list; subtitles keep going.
        }
        inflight = false
    }

    internal fun seeked(activeSession: String, activeMedia: String) {
        if (closed || activeSession != sid || activeMedia != mediaKey) return
        generation++
        inflight = false
        cursor = 0
        player.reset()
        receiver.resetForSeek(sid, mediaKey)
        lastPosition = null
        lastFetchAt = 0L
    }

    internal fun close() {
        if (closed) return
        closed = true
        generation++
        inflight = false
        player.close()
        receiver.close()
        secret.fill(0)
    }
}
