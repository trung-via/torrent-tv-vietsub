// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

fun main() {
    val c = P4VoiceoverTimeline
    check(c.decision(500, 1000, 1800, true, false) == "WAIT")
    check(c.decision(900, 1000, 1800, true, false) == "PLAY")
    check(c.decision(1200, 1000, 1800, true, false) == "PLAY")
    check(c.decision(1720, 1000, 1800, true, false) == "SKIP")
    check(c.decision(1800, 1000, 1800, true, false) == "SKIP")
    check(c.decision(1000, 1000, 1800, false, false) == "PAUSE")
    check(c.decision(1000, 1000, 1800, true, true) == "PAUSE")
    check(!c.discontinuity(null, 1000))
    check(!c.discontinuity(1000, 1450))
    check(c.discontinuity(4000, 300))
    check(c.discontinuity(1000, 6000))
    println("P4_VOICEOVER_VLC_CLOCK_SEEK_PAUSE_BUFFER_PASS_NOT_TV_AUDIO")
}
