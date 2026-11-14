"""Source-pinned P3 selected-media overlay on disposable P4 PlayerActivity.

Requires already composed G1+G2+P4 activity. All checks are source-only.
Never edits the running Android app, no Gradle/ADB, sockets or provider calls.
Default dry-run; --apply only on an EXPLICIT disposable source checkout.
"""
from __future__ import annotations

import argparse
from pathlib import Path

PKG = Path("android/app/src/main/java/com/spacesarmat/omp/player")
KOTLIN_FILE = "P3SelectedMediaPublisher.kt"
ACTIVITY_FILE = "PlayerActivity.kt"

LOAD = "        session.load(r, next)\n        flow.reset()"
ITEM = "        if (!switcher.goTo(i)) return\n        cancelCountdown()"
CLOSE = "        closedSent = true\n        commitPendingSeek()"
MENU = '        add("Hủy ghép đôi PC Vietsub AI", "AD01.12") {'

MENU_ROW = """        add(if (P3SelectedMediaPublisher.enabled(applicationContext))
                "Tắt tín hiệu tự tìm Vietsub" else "Bật tín hiệu tự tìm Vietsub",
                "AD01.13") {
            val want = !P3SelectedMediaPublisher.enabled(applicationContext)
            val ok = P3SelectedMediaPublisher.setEnabled(applicationContext, want)
            showMessage(
                if (!ok) "Cần ghép PC Vietsub AI trước."
                else if (want) "Đã bật tín hiệu chọn phim về PC."
                else "Đã tắt tín hiệu chọn phim về PC.",
                !ok,
            )
        }
"""


def patch_activity(text: str) -> str:
    if not isinstance(text, str) or (
        "P3SelectedMediaPublisher.accepted(" in text
        or "P3SelectedMediaPublisher.closed(" in text
    ):
        raise ValueError("P3_ACTIVITY_ALREADY_APPLIED")
    if (text.count("internal fun receiveP4Revision(") != 1
            or text.count("P4OwnerBootstrap.consume(applicationContext)") < 1
            or text.count('add("Hủy ghép đôi PC Vietsub AI"') != 1):
        raise ValueError("P3_REQUIRES_EXACT_P4_COMPOSED_SOURCE")
    rules = (
        (LOAD, """        session.load(r, next)
        P3SelectedMediaPublisher.accepted(
            applicationContext, session.request, session.index,
            "PLAY_REQUEST_ACCEPTED")
        flow.reset()"""),
        (ITEM, """        if (!switcher.goTo(i)) return
        P3SelectedMediaPublisher.accepted(
            applicationContext, session.request, session.index,
            "NEXT_QUEUE_ITEM_ACCEPTED")
        cancelCountdown()"""),
        (CLOSE, """        closedSent = true
        P3SelectedMediaPublisher.closed(applicationContext)
        commitPendingSeek()"""),
        (MENU, MENU_ROW + MENU),
    )
    for original, _ in rules:
        if text.count(original) != 1:
            raise ValueError("P3_SOURCE_ANCHOR_DRIFT")
    for original, updated in rules:
        text = text.replace(original, updated, 1)
    if text.count("P3SelectedMediaPublisher.accepted(") != 2:
        raise ValueError("P3_SOURCE_CALLBACK_COUNT_INVALID")
    if text.count("P3SelectedMediaPublisher.closed(") != 1:
        raise ValueError("P3_SOURCE_CLOSE_COUNT_INVALID")
    return text


def run(root: Path, *, apply: bool = False) -> str:
    if not isinstance(root, Path) or not root.is_absolute():
        raise ValueError("P3_EXPLICIT_ABSOLUTE_SOURCE_ROOT_REQUIRED")
    source = root / PKG
    needed = ["P4PinnedTls.kt", "P4PairingStore.kt", "P4LanClient.kt",
              "P4ActivationClient.kt", ACTIVITY_FILE]
    if not all((source / path).is_file() and not (source / path).is_symlink()
               for path in needed):
        raise ValueError("P3_REQUIRES_DISPOSABLE_P4_COMPOSED_CHECKOUT")
    target = source / ACTIVITY_FILE
    dest = source / KOTLIN_FILE
    if dest.exists() or dest.is_symlink():
        raise ValueError("P3_PUBLISHER_ALREADY_EXISTS")
    original = target.read_text(encoding="utf-8")
    updated = patch_activity(original)
    helper = (Path(__file__).resolve().parent / KOTLIN_FILE)
    if not helper.is_file() or helper.is_symlink():
        raise ValueError("P3_PINNED_PUBLISHER_SOURCE_MISSING")
    if "internal object P3SelectedMediaPublisher" not in helper.read_text("utf-8"):
        raise ValueError("P3_PINNED_PUBLISHER_INVALID")
    if not apply:
        return "P3_NATIVE_SOURCE_DRY_RUN_PASS"
    dest.write_bytes(helper.read_bytes())
    target.write_text(updated, encoding="utf-8")
    return "P3_NATIVE_SOURCE_APPLIED_DISPOSABLE_ONLY"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    print(run(args.source_root, apply=args.apply))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
