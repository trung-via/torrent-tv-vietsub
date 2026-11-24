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
    check(c.discontinuity(2000, 1200)) // small reverse seek must re-arm
    check(!c.discontinuity(2000, 1700)) // tolerate clock jitter
    check(c.discontinuity(1000, 6000))
    check(c.speedToFit(1000, 1000, 2000, 1000) == 1.0f)
    check(c.speedToFit(1000, 1000, 2000, 1200) == 1.2f)
    check(c.speedToFit(1300, 1000, 2000, 1000) == null)
    check(c.speedToFit(2000, 1000, 2000, 100) == null)
    println("P4_VOICEOVER_VLC_CLOCK_SEEK_PAUSE_BUFFER_PASS_NOT_TV_AUDIO")
}
