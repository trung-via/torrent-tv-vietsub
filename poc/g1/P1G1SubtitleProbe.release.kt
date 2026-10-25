// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context

/** Release never reads the G1 marker/file or injects a debug subtitle. */
internal object P1G1SubtitleProbe {
    fun prepare(@Suppress("UNUSED_PARAMETER") context: Context, r: PlayRequest): PlayRequest = r
}
