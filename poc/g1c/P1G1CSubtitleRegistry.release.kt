// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context

/** Release: no file access, marker gate, persistent debug registry or injection. */
internal object P1G1CSubtitleRegistry {
    fun prepare(@Suppress("UNUSED_PARAMETER") context: Context, r: PlayRequest): PlayRequest = r
}
