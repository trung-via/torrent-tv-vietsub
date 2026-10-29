// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.CharacterCodingException
import java.security.MessageDigest
import java.util.Locale

/** User-initiated, release-capable sidecar registry; unrelated to debug G1c. */
internal object P1ProductionSubtitles {
    private const val PREFS = "p1-production-subtitles"
    private const val FOLDER = "p1-production-subtitles"
    private const val MAX = 256 * 1024
    private const val LABEL = "Vietsub rời (đã lưu)"
    private const val WARNING = "Phụ đề rời đã lưu không khả dụng. Kiểm tra file SRT/VTT."
    private val profileRx = Regex("[A-Za-z0-9_-]{1,80}")
    private val hashRx = Regex("[0-9a-fA-F]{40}")
    private val digestRx = Regex("[0-9a-f]{64}")
    private val srtRx = Regex("""(?m)^\d{1,6}\r?\n\d{2}:\d{2}:\d{2},\d{3}[ \t]*-->[ \t]*\d{2}:\d{2}:\d{2},\d{3}""")
    private val vttRx = Regex("""(?m)^(?:\d{2}:)?\d{2}:\d{2}\.\d{3}[ \t]*-->[ \t]*(?:\d{2}:)?\d{2}:\d{2}\.\d{3}""")

    data class Prepared(val request: PlayRequest, val warning: String? = null)
    private data class Validated(val ext: String, val sha: String)

    private fun sha(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(Locale.ROOT, it.toInt() and 255)
        }

    fun mediaKey(r: PlayRequest?, index: Int): String? {
        if (r == null || r.engine != EngineMode.VLC || index !in r.queue.indices) return null
        val profile = r.serverProfileId ?: return null
        val item = r.queue[index]
        val hash = item.hash ?: return null
        val fileIndex = item.fileIndex ?: return null
        if (!profileRx.matches(profile) || !hashRx.matches(hash) || fileIndex < 0) return null
        return "media." + sha(("prod\u0000" + profile + "\u0000" +
            hash.lowercase(Locale.ROOT) + "\u0000" + fileIndex).toByteArray(Charsets.UTF_8))
    }

    /** Pure parser boundary shared with JVM unit tests. No Android context or provider required. */
    internal fun detectedExtension(bytes: ByteArray): String? {
        if (bytes.isEmpty() || bytes.size > MAX) return null
        val text = try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString().removePrefix("\uFEFF")
        } catch (_: CharacterCodingException) { return null }
        if ('\u0000' in text) return null
        return when {
            (text.startsWith("WEBVTT\n") || text.startsWith("WEBVTT\r\n")) &&
                vttRx.containsMatchIn(text) -> "vtt"
            srtRx.containsMatchIn(text) -> "srt"
            else -> null
        }
    }

    private fun validate(bytes: ByteArray): Validated? =
        detectedExtension(bytes)?.let { Validated(it, sha(bytes)) }

    /** Never let the preceding episode's production ON/OFF choice decide this episode. */
    internal fun transitionPicks(
        selection: String?, trusted: Boolean, fallback: List<TrackPick>,
    ): List<TrackPick> = when (selection) {
        "on" -> if (trusted) listOf(TrackPick(label = LABEL)) else fallback
        "off" -> listOf(TrackPick(off = true))
        else -> fallback
    }

    /** Only the exact saved external sidecar can satisfy the persisted ON choice.
     *  Null: ordinary OMP picks; -1: external VLC ES has not arrived yet.
     *  Source ownership/digest validation remains in prepare(), not this pure test seam.
     */
    internal fun savedSidecarTrackIndex(
        picks: List<TrackPick>, files: List<SubFile>, tracks: List<EngineTrack>,
    ): Int? {
        if (picks.size != 1 || picks[0] != TrackPick(label = LABEL)) return null
        val matches = files.indices.filter { i ->
            files[i].label == LABEL && files[i].url.startsWith("file://")
        }
        if (matches.size != 1) return null
        return tracks.indexOfFirst { it.external == matches.single() }
    }

    data class ItemTransition(val picks: List<TrackPick>, val warning: String? = null)

    fun hasAnySaved(ctx: Context, r: PlayRequest): Boolean =
        r.engine == EngineMode.VLC && r.queue.indices.any { hasSaved(ctx, r, it) }

    /** Re-evaluate the target item before goTo opens it; only ON requires a verified file. */
    fun forItem(ctx: Context, r: PlayRequest?, i: Int, fallback: List<TrackPick>): ItemTransition {
        val k = mediaKey(r, i) ?: return ItemTransition(fallback)
        val p = prefs(ctx)
        val stored = p.getString("sha.$k", null) ?: return ItemTransition(fallback)
        val choice = p.getString("selection.$k", null)
        if (choice != "on") return ItemTransition(transitionPicks(choice, false, fallback))
        val ext = p.getString("ext.$k", null)
        if (!digestRx.matches(stored) || ext !in listOf("srt", "vtt")) {
            return ItemTransition(fallback, WARNING)
        }
        val v = Validated(ext!!, stored)
        val saved = file(ctx, k, v)
        val item = r?.queue?.getOrNull(i) ?: return ItemTransition(fallback, WARNING)
        val expectedUri = Uri.fromFile(saved).toString()
        val trusted = try {
            saved.isFile && saved.canRead() && saved.length() in 1L..MAX.toLong() &&
                validate(saved.readBytes()) == v &&
                item.subtitles.any { it.label == LABEL && it.url == expectedUri } &&
                item.subtitles.none { it.label == LABEL && it.url != expectedUri }
        } catch (_: Exception) { false }
        return ItemTransition(transitionPicks(choice, trusted, fallback), if (trusted) null else WARNING)
    }

    private fun folder(ctx: Context) = File(ctx.filesDir, FOLDER)
    private fun file(ctx: Context, k: String, v: Validated): File =
        File(folder(ctx), k.removePrefix("media.") + "." + v.sha + "." + v.ext)
    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    fun hasSaved(ctx: Context, r: PlayRequest?, i: Int): Boolean {
        val k = mediaKey(r, i) ?: return false
        return prefs(ctx).contains("sha.$k")
    }

    private fun readDocument(ctx: Context, uri: Uri): ByteArray {
        val stream = ctx.contentResolver.openInputStream(uri) ?: throw IOException("No document")
        stream.use {
            val result = ByteArrayOutputStream()
            val part = ByteArray(8192)
            var count = 0
            while (true) {
                val n = it.read(part)
                if (n < 0) break
                count += n
                if (count > MAX) throw IOException("Too large")
                result.write(part, 0, n)
            }
            return result.toByteArray()
        }
    }

    /** Must be invoked for an explicit Android document pick, not silently at startup. */
    @Synchronized fun importSelected(ctx: Context, uri: Uri, r: PlayRequest, i: Int): Boolean {
        val k = mediaKey(r, i) ?: return false
        val bytes = readDocument(ctx, uri)
        val v = validate(bytes) ?: return false
        val dir = folder(ctx)
        if (!dir.isDirectory && !dir.mkdirs()) return false
        val target = file(ctx, k, v)
        var created = false
        if (!target.exists()) {
            val tmp = File.createTempFile("pending-", ".tmp", dir)
            try {
                tmp.outputStream().use { out ->
                    out.write(bytes)
                    out.flush()
                }
                if (!tmp.renameTo(target)) return false
                created = true
            } finally { tmp.delete() }
        } else if (!target.isFile || target.length() > MAX ||
            validate(target.readBytes()) != v) {
            return false
        }
        val p = prefs(ctx)
        val old = p.getString("sha.$k", null)
        val oldExt = p.getString("ext.$k", null)
        if (!p.edit().putString("sha.$k", v.sha).putString("ext.$k", v.ext)
                .putString("selection.$k", "on").commit()) {
            if (created) target.delete()
            return false
        }
        if (old != null && digestRx.matches(old) && oldExt in listOf("srt", "vtt") &&
            (old != v.sha || oldExt != v.ext)) {
            file(ctx, k, Validated(oldExt!!, old)).delete()
        }
        return true
    }

    @Synchronized fun removeSaved(ctx: Context, r: PlayRequest?, i: Int): Boolean {
        val k = mediaKey(r, i) ?: return false
        val p = prefs(ctx)
        val old = p.getString("sha.$k", null) ?: return false
        val oldExt = p.getString("ext.$k", null)
        if (!p.edit().remove("sha.$k").remove("ext.$k").remove("selection.$k").commit()) return false
        if (digestRx.matches(old) && oldExt in listOf("srt", "vtt")) {
            file(ctx, k, Validated(oldExt!!, old)).delete()
        }
        return true
    }

    fun noteTrackChoice(ctx: Context, r: PlayRequest?, i: Int, choice: TrackChoice) {
        if (choice.audio) return
        val k = mediaKey(r, i) ?: return
        val p = prefs(ctx)
        if (!p.contains("sha.$k")) return
        val value = when {
            choice.off -> "off"
            choice.label == LABEL -> "on"
            else -> "other"
        }
        p.edit().putString("selection.$k", value).apply()
    }

    fun prepare(ctx: Context, r: PlayRequest): Prepared {
        if (r.engine != EngineMode.VLC || r.index !in r.queue.indices) return Prepared(r)
        val p = prefs(ctx)
        val queue = r.queue.toMutableList()
        var modified = false
        var currentTrusted = false
        var warning: String? = null
        for (i in queue.indices) {
            val k = mediaKey(r, i) ?: continue
            val stored = p.getString("sha.$k", null) ?: continue
            val ext = p.getString("ext.$k", null)
            if (!digestRx.matches(stored) || ext !in listOf("srt", "vtt")) continue
            val v = Validated(ext!!, stored)
            val f = file(ctx, k, v)
            val good = try {
                f.isFile && f.canRead() && f.length() in 1L..MAX.toLong() &&
                    validate(f.readBytes()) == v
            } catch (_: Exception) { false }
            if (!good) {
                if (i == r.index && p.getString("selection.$k", null) == "on") warning = WARNING
                continue
            }
            val expectedUri = Uri.fromFile(f).toString()
            // Reject a subtitle from a torrent/page that impersonates our label
            // but points to a different URL. The file URI must match exactly.
            if (queue[i].subtitles.any { it.label == LABEL && it.url != expectedUri }) {
                if (i == r.index && p.getString("selection.$k", null) == "on") warning = WARNING
                continue
            }
            if (queue[i].subtitles.none { it.label == LABEL && it.url == expectedUri }) {
                queue[i] = queue[i].copy(subtitles = queue[i].subtitles +
                    SubFile(expectedUri, LABEL, v.ext, "vi"))
                modified = true
            }
            if (i == r.index) currentTrusted = true
        }
        if (!modified && warning == null && !currentTrusted) return Prepared(r)
        val base = if (modified) r.copy(queue = queue) else r
        val k = mediaKey(r, r.index) ?: return Prepared(base, warning)
        if (!currentTrusted) return Prepared(base, warning)
        val result = when (p.getString("selection.$k", null)) {
            "on" -> base.copy(subPick = listOf(TrackPick(label = LABEL)), subtitlesOn = true)
            "off" -> base.copy(subPick = listOf(TrackPick(off = true)), subtitlesOn = false)
            else -> base
        }
        return Prepared(result, warning)
    }
}
