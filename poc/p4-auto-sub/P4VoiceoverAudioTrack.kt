// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.util.TreeMap

/**
 * PCM16 48 kHz speech sidecar mixed by Android with the existing VLC sound.
 *
 * prepare() runs OFF the Activity UI thread, verifies the exact WAV layout,
 * and loads MODE_STATIC without any network/model operations. The Activity
 * invokes enqueue/tick/reset/close on its main thread. One cue may play at
 * a time; pause, seek, buffering or a film switch revokes playback promptly.
 * Whether SPDIF/soundbar actually mixes both tracks needs REAL Redmi proof.
 */
internal class P4VoiceoverAudioTrack {
    internal class Prepared private constructor(
        val offer: P4VoiceoverOffer, private val player: AudioTrack,
    ) {
        private var running = false
        internal fun play() {
            if (!running) {
                player.play()
                running = true
            }
        }
        internal fun pause() {
            if (running) {
                player.pause()
                running = false
            }
        }
        internal fun close() {
            try { pause() } catch (_: Exception) {}
            try { player.flush() } catch (_: Exception) {}
            player.release()
        }

        companion object {
            internal fun fromWav(offer: P4VoiceoverOffer, wav: ByteArray): Prepared {
                fun u16(at: Int): Int =
                    (wav[at].toInt() and 255) or ((wav[at + 1].toInt() and 255) shl 8)
                fun u32(at: Int): Long =
                    (u16(at).toLong() or (u16(at + 2).toLong() shl 16))
                fun chunk(at: Int, text: String): Boolean =
                    wav.copyOfRange(at, at + 4).contentEquals(text.toByteArray(Charsets.US_ASCII))
                if (wav.size !in 46..3_000_000 || !chunk(0, "RIFF") ||
                    !chunk(8, "WAVE") || !chunk(12, "fmt ") ||
                    !chunk(36, "data") || u32(4) != wav.size.toLong() - 8L ||
                    u32(16) != 16L || u16(20) != 1 || u16(22) != 1 ||
                    u32(24) != 48_000L || u32(28) != 96_000L ||
                    u16(32) != 2 || u16(34) != 16 ||
                    u32(40) != wav.size.toLong() - 44L ||
                    (wav.size - 44) % 2 != 0) {
                    throw IllegalArgumentException("P4_VOICE_WAV_PCM_FORMAT_INVALID")
                }
                val expectedMs = ((wav.size.toLong() - 44L) * 1000L + 48_000L) / 96_000L
                if (offer.sampleRate != 48_000 ||
                    kotlin.math.abs(expectedMs - offer.durationMs.toLong()) > 2L) {
                    throw IllegalArgumentException("P4_VOICE_WAV_DURATION_INVALID")
                }
                val pcmLength = wav.size - 44
                val track = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    .setAudioFormat(AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(48_000)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(pcmLength).build()
                try {
                    if (track.state != AudioTrack.STATE_INITIALIZED ||
                        track.write(wav, 44, pcmLength, AudioTrack.WRITE_BLOCKING) != pcmLength) {
                        throw IllegalStateException("P4_VOICE_AUDIO_TRACK_NOT_READY")
                    }
                    return Prepared(offer, track)
                } catch (exc: Exception) {
                    track.release()
                    throw exc
                }
            }
        }
    }

    private val pending = TreeMap<Long, Prepared>()
    private var active: Prepared? = null
    private val queuedKeys = mutableSetOf<String>()
    internal val isSpeaking: Boolean get() = active != null

    /** Main-thread only. No silent overwrite of another cue at the same time. */
    internal fun enqueue(prepared: Prepared): Boolean {
        val offer = prepared.offer
        if (queuedKeys.contains(offer.ttsKey)) {
            prepared.close()
            return true
        }
        if (pending.size >= 8 || pending.containsKey(offer.startMs)) {
            prepared.close()
            return false
        }
        pending[offer.startMs] = prepared
        queuedKeys.add(offer.ttsKey)
        return true
    }

    /** Called on the OMP Activity clock, not the TTS/network worker clock. */
    internal fun tick(positionMs: Long, playing: Boolean, buffering: Boolean): Boolean {
        val current = active
        if (current != null) {
            val cue = current.offer
            val speechEnd = minOf(cue.endMs, cue.startMs + cue.durationMs.toLong() + 150L)
            if (positionMs < cue.startMs - 500L || positionMs >= speechEnd) {
                current.close()
                active = null
            } else {
                try {
                    if (playing && !buffering) current.play() else current.pause()
                    return playing && !buffering
                } catch (_: Exception) {
                    current.close()
                    active = null
                }
            }
        }
        while (pending.isNotEmpty()) {
            val first = pending.firstEntry()
            val cue = first.value.offer
            when (P4VoiceoverTimeline.decision(
                    positionMs, cue.startMs, cue.endMs, playing, buffering)) {
                "PAUSE", "WAIT" -> return false
                "SKIP" -> {
                    pending.pollFirstEntry().value.close()
                    continue
                }
                "PLAY" -> {
                    val ready = pending.pollFirstEntry().value
                    try {
                        ready.play()
                        active = ready
                        return true
                    } catch (_: Exception) {
                        ready.close()
                        continue
                    }
                }
            }
        }
        return false
    }

    internal fun reset() {
        active?.close()
        active = null
        pending.values.forEach { it.close() }
        pending.clear()
        queuedKeys.clear()
    }

    internal fun close() = reset()
}
