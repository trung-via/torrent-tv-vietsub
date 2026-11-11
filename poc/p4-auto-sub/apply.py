#!/usr/bin/env python3
"""P4 app-private G1 bytes import overlay for an EXPLICIT disposable G1+G2 checkout.

- Source-only, default dry-run. Does not send provider requests, start a socket,
  install an APK, modify the runner/TV or arm a live player.
- Adds a byte import hook behind a future authenticated P4SignedReceiver gate.
- Keeps human-selected Android OpenDocument import behavior unchanged.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys

PKG = Path("android/app/src/main/java/com/spacesarmat/omp/player")
SOURCE_FILE = "P1ProductionSubtitles.kt"
RECEIVER_FILE = "P4SignedReceiver.kt"
LAN_CLIENT_FILE = "P4LanClient.kt"

OLD_HEAD = '''    @Synchronized fun importSelected(ctx: Context, uri: Uri, r: PlayRequest, i: Int): Boolean {
        val k = mediaKey(r, i) ?: return false
        val bytes = readDocument(ctx, uri)
        val v = validate(bytes) ?: return false'''

NEW_HEAD = '''    @Synchronized fun importSelected(ctx: Context, uri: Uri, r: PlayRequest, i: Int): Boolean {
        val bytes = readDocument(ctx, uri)
        return saveVerifiedBytes(ctx, bytes, r, i, automatic = false)
    }

    /**
     * Internal-only P4 bytes entrypoint after verified session/media/HMAC in
     * P4SignedReceiver. No Android picker, remote URL or arbitrary file path.
     * Actual TV callback MUST recheck the live session and ON preference.
     */
    @Synchronized internal fun importAutomaticBytes(
        ctx: Context, bytes: ByteArray, r: PlayRequest, i: Int, expectedMediaKey: String,
    ): Boolean {
        val key = mediaKey(r, i) ?: return false
        if (key != expectedMediaKey) return false
        val p = prefs(ctx)
        if (!p.getBoolean("ai.$key", false) ||
            p.getString("selection.$key", null) != "on") return false
        return saveVerifiedBytes(ctx, bytes, r, i, automatic = true)
    }

    private fun saveVerifiedBytes(
        ctx: Context, bytes: ByteArray, r: PlayRequest, i: Int, automatic: Boolean,
    ): Boolean {
        val k = mediaKey(r, i) ?: return false
        val v = validate(bytes) ?: return false'''

OLD_COMMIT = '''        val p = prefs(ctx)
        val old = p.getString("sha.$k", null)
        val oldExt = p.getString("ext.$k", null)
        if (!p.edit().putString("sha.$k", v.sha).putString("ext.$k", v.ext)
                .putString("selection.$k", "on").commit()) {'''

NEW_COMMIT = '''        val p = prefs(ctx)
        // Check again immediately before commit: never override a user's OFF/OTHER
        // selection due to an asynchronous automatic revision arriving late.
        if (automatic && (!p.getBoolean("ai.$k", false) ||
                p.getString("selection.$k", null) != "on")) {
            if (created) target.delete()
            return false
        }
        val old = p.getString("sha.$k", null)
        val oldExt = p.getString("ext.$k", null)
        if (!p.edit().putString("sha.$k", v.sha).putString("ext.$k", v.ext)
                .putString("selection.$k", "on").commit()) {'''


def patch_g1(text: str) -> str:
    if "importAutomaticBytes(" in text:
        raise ValueError("P4_ALREADY_APPLIED")
    for key, replacement in [(OLD_HEAD, NEW_HEAD), (OLD_COMMIT, NEW_COMMIT)]:
        if text.count(key) != 1:
            raise ValueError("P4_G1_EXACT_SOURCE_ANCHOR_INVALID")
        text = text.replace(key, replacement, 1)
    # Explicit per-film Vietsub AI ON can exist *before* the first SRT.
    # A normal manual subtitle choice is NOT an opt-in for network delivery.
    choice_anchor = "    fun hasSaved(ctx: Context, r: PlayRequest?, i: Int): Boolean {"
    ai_opt_in = '''    @Synchronized internal fun setAutomaticOptIn(
        ctx: Context, r: PlayRequest?, i: Int, enabled: Boolean,
    ): Boolean {
        if (r?.engine != EngineMode.VLC) return false
        val k = mediaKey(r, i) ?: return false
        val p = prefs(ctx)
        val editor = p.edit()
        if (enabled) {
            // This method must be called ONLY by the explicit Vietsub AI UI action.
            editor.putBoolean("ai.$k", true).putString("selection.$k", "on")
        } else {
            editor.remove("ai.$k").putString("selection.$k", "off")
        }
        return editor.commit()
    }

'''
    if text.count(choice_anchor) != 1:
        raise ValueError("P4_AI_OPTIN_ANCHOR_INVALID")
    text = text.replace(choice_anchor, ai_opt_in + choice_anchor, 1)
    # Selection persistence and automatic byte commits must use the same
    # monitor to serialize user OFF/OTHER against an in-flight P4 import.
    track_choice = "    fun noteTrackChoice(ctx: Context, r: PlayRequest?, i: Int, choice: TrackChoice) {"
    if text.count(track_choice) != 1:
        raise ValueError("P4_TRACK_CHOICE_ANCHOR_INVALID")
    text = text.replace(track_choice, "    @Synchronized " + track_choice.lstrip(), 1)
    old_choice_write = '        p.edit().putString("selection.$k", value).apply()'
    new_choice_write = '''        val edit = p.edit().putString("selection.$k", value)
        if (value != "on") edit.remove("ai.$k")
        edit.apply()'''
    if text.count(old_choice_write) != 1:
        raise ValueError("P4_TRACK_CHOICE_WRITE_ANCHOR_INVALID")
    text = text.replace(old_choice_write, new_choice_write, 1)
    # Query AI activation independently of manually saved track.
    choice_anchor = "    fun hasSaved(ctx: Context, r: PlayRequest?, i: Int): Boolean {"
    choice_method = '''    @Synchronized internal fun automaticChoice(
        ctx: Context, r: PlayRequest?, i: Int,
    ): String {
        val key = mediaKey(r, i) ?: return "OTHER"
        val p = prefs(ctx)
        return when (p.getString("selection.$key", null)) {
            "on" -> if (p.getBoolean("ai.$key", false)) "ON" else "OTHER"
            "off" -> "OFF"
            else -> "OTHER"
        }
    }

'''
    if text.count(choice_anchor) != 1:
        raise ValueError("P4_AUTOMATIC_CHOICE_ANCHOR_INVALID")
    text = text.replace(choice_anchor, choice_method + choice_anchor, 1)
    if text.count("fun importSelected(") != 1 or text.count("fun importAutomaticBytes(") != 1:
        raise ValueError("P4_IMPORT_ENTRYPOINT_INVALID")
    return text


def run(root: Path, *, apply: bool = False) -> None:
    root = root.resolve(strict=True)
    if not root.is_dir() or not root.name.startswith("p1-g1-prod-"):
        raise ValueError("P4_DISPOSABLE_G1_CHECKOUT_REQUIRED")
    pkg = root / PKG
    g1 = pkg / SOURCE_FILE
    g2 = pkg / "G2RefreshInPlace.kt"
    g2_recovery = pkg / "G2RefreshRecovery.kt"
    activity = pkg / "PlayerActivity.kt"
    if not all(p.is_file() for p in (g1, g2, g2_recovery, activity)):
        raise ValueError("P4_G1_G2_COMPOSITE_SOURCE_REQUIRED")
    existing = g1.read_bytes()
    if len(existing) > 100_000:
        raise ValueError("P4_G1_SOURCE_SIZE_INVALID")
    try:
        source = existing.decode("utf-8-sig")
    except UnicodeError:
        raise ValueError("P4_G1_SOURCE_UTF8_INVALID") from None
    line_sep = "\r\n" if b"\r\n" in existing else "\n"
    patched = patch_g1(source.replace("\r\n", "\n")).replace("\n", line_sep)
    native_sources = [Path(__file__).with_name(name) for name in
                      (RECEIVER_FILE, LAN_CLIENT_FILE)]
    native_targets = [pkg / p.name for p in native_sources]
    if any(not p.is_file() for p in native_sources) or any(p.exists() for p in native_targets):
        raise ValueError("P4_NATIVE_SOURCE_MISSING_OR_PRESENT")
    raw_activity = activity.read_bytes()
    if "G2RefreshInPlace.prepare" not in raw_activity.decode("utf-8-sig"):
        raise ValueError("P4_LIVE_G2_ACTIVITY_HOOK_NOT_PRESENT")
    # Reuse a standalone bounded source patch module to keep activity anchors
    # readable and testable without a running Android device.
    import importlib.util
    activity_patch_path = Path(__file__).with_name("activity_patch.py")
    spec = importlib.util.spec_from_file_location("p4_activity_patch", activity_patch_path)
    if spec is None or spec.loader is None:
        raise ValueError("P4_ACTIVITY_PATCH_MODULE_MISSING")
    patch_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(patch_module)
    original_activity = raw_activity.decode("utf-8-sig")
    activity_nl = "\r\n" if b"\r\n" in raw_activity else "\n"
    patched_activity = patch_module.patch_activity(
        original_activity.replace("\r\n", "\n")).replace("\n", activity_nl)
    print("P4_G1_G2_OVERLAY_PREFLIGHT_PASS source_sha256=" +
          hashlib.sha256(existing).hexdigest() + " dry_run=" + str(not apply))
    if not apply:
        return
    # Source-only disposable copy, no running application/TV side effect.
    g1.write_text(patched, encoding="utf-8", newline="")
    for src, dst in zip(native_sources, native_targets):
        dst.write_bytes(src.read_bytes())
    activity.write_bytes(
        (b"\xef\xbb\xbf" if raw_activity.startswith(b"\xef\xbb\xbf") else b"") +
        patched_activity.encode("utf-8"))
    print("P4_NATIVE_ACTIVITY_BRIDGE_SOURCE_APPLIED_NOT_ANDROID_BUILT_NOT_TV")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--omp-root", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        run(args.omp_root, apply=args.apply)
    except (ValueError, FileNotFoundError, OSError, UnicodeError) as exc:
        print("P4_STOP: " + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
