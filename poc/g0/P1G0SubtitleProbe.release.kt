// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context

/**
 * P1 G0 release variant deliberately contains no asset reader, marker gate or
 * test-fixture injection. This API exists solely to keep the upstream call site
 * identical across Android build variants.
 */
internal object P1G0SubtitleProbe {
    fun prepare(@Suppress("UNUSED_PARAMETER") context: Context, r: PlayRequest): PlayRequest = r
}
