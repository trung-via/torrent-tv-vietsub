// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import java.io.File
import java.net.URI

/** Pure guard for a G1-owned old sidecar when replacing it with a newer cumulative SRT/VTT. */
internal object G2RefreshDecision {
    /** A picker result must still belong to the same VLC queue entry, never a later item. */
    fun matchesCurrent(pickerKey: String?, currentKey: String?, pickerIndex: Int, currentIndex: Int,
                       isVlc: Boolean, closed: Boolean): Boolean =
        !closed && isVlc && pickerKey != null && pickerKey == currentKey && pickerIndex == currentIndex

    /** The G1 `prepare()` method trusted this scoped file at playback start. After import it may be deleted. */
    fun isScopedOldFile(url: String, mediaKey: String, folder: File): Boolean {
        return try {
        val keyPart = mediaKey.removePrefix("media.")
        if (!Regex("^[0-9a-f]{64}$").matches(keyPart)) return false
        val uri = URI(url)
        if (uri.scheme != "file" || uri.rawAuthority != null || uri.rawQuery != null || uri.rawFragment != null) return false
        val f = File(uri).canonicalFile
        val scope = folder.canonicalFile
        f.parentFile == scope && Regex("^${Regex.escape(keyPart)}\\.[0-9a-f]{64}\\.(srt|vtt)$").matches(f.name)
        } catch (_: Exception) { false }
    }
}