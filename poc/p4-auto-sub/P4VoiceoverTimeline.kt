// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

/**
 * Small, JVM-testable alignment policy for VieNeu cues versus OMP's VLC clock.
 * Never infer playback position from wall time; buffering/pausing stops narration.
 */
internal object P4VoiceoverTimeline {
    fun discontinuity(previousMs: Long?, currentMs: Long): Boolean =
        previousMs != null &&
        (currentMs + 500L < previousMs || currentMs - previousMs > 2_500L)

    fun decision(
        positionMs: Long, startMs: Long, endMs: Long,
        playing: Boolean, buffering: Boolean,
    ): String {
        if (!playing || buffering) return "PAUSE"
        if (positionMs < startMs - 130L) return "WAIT"
        if (positionMs >= endMs || positionMs > startMs + 650L) return "SKIP"
        return "PLAY"
    }
}
