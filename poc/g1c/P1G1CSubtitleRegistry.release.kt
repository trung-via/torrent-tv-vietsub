// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context

/** Release: no file access, marker gate, persistent debug registry or injection. */
internal object P1G1CSubtitleRegistry {
    internal data class Prepared(val request: PlayRequest, val warning: String? = null)

    fun prepare(@Suppress("UNUSED_PARAMETER") context: Context, r: PlayRequest): Prepared =
        Prepared(r)
    fun noteTrackChoice(
        @Suppress("UNUSED_PARAMETER") context: Context,
        @Suppress("UNUSED_PARAMETER") r: PlayRequest?,
        @Suppress("UNUSED_PARAMETER") index: Int,
        @Suppress("UNUSED_PARAMETER") choice: TrackChoice,
    ) {}

}
