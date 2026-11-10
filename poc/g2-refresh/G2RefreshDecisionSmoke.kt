// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import java.io.File

fun main() {
    val mk = "media." + "a".repeat(64)
    val dir = createTempDir(prefix = "g2-refresh-")
    val file = File(dir, "${"a".repeat(64)}.${"b".repeat(64)}.srt")
    file.writeText("synthetic-only")
    val u = file.toURI().toString()
    var count = 0
    fun checkCase(ok: Boolean) { check(ok); count++ }
    checkCase(G2RefreshDecision.matchesCurrent(mk, mk, 2, 2, true, false))
    checkCase(!G2RefreshDecision.matchesCurrent(mk, mk, 2, 3, true, false))
    checkCase(!G2RefreshDecision.matchesCurrent(mk, mk, 2, 2, false, false))
    checkCase(!G2RefreshDecision.matchesCurrent(mk, mk, 2, 2, true, true))
    checkCase(!G2RefreshDecision.matchesCurrent(null, mk, 2, 2, true, false))
    checkCase(!G2RefreshDecision.matchesCurrent(mk, "media." + "c".repeat(64), 2, 2, true, false))
    checkCase(G2RefreshDecision.isScopedOldFile(u, mk, dir))
    checkCase(!G2RefreshDecision.isScopedOldFile(u, "media." + "c".repeat(64), dir))
    checkCase(!G2RefreshDecision.isScopedOldFile(u, mk, File(dir, "unrelated")))
    checkCase(!G2RefreshDecision.isScopedOldFile("https://example.test/captions.srt", mk, dir))
    checkCase(!G2RefreshDecision.isScopedOldFile(u + "?x=1", mk, dir))
    checkCase(!G2RefreshDecision.isScopedOldFile(File(dir,"${"a".repeat(64)}.${"b".repeat(64)}.exe").toURI().toString(), mk, dir))
    checkCase(!G2RefreshDecision.isScopedOldFile(File(dir.parentFile,"${"a".repeat(64)}.${"b".repeat(64)}.srt").toURI().toString(), mk, dir))
    checkCase(!G2RefreshDecision.isScopedOldFile("file:///../../${"a".repeat(64)}.${"b".repeat(64)}.srt", mk, dir))
    println("G2 Refresh policy $count/$count PASS (local Kotlin/JVM smoke)")
    file.delete(); dir.delete()
}