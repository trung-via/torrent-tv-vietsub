"""Print an exact, pre-merge Owner Brain review receipt (never post it).

Usage:
  python poc/g1-p2-auto/render_brain_verdict.py --pr 57 \
    --head-sha <40-hex> --base-sha <40-hex> --decision PASS

This does not review a PR, attest CI, modify GitHub or authorize a build.
Brain must independently validate current PR HEAD/base, diff and CI first.
Only a truthful reviewed verdict, posted by the repository OWNER before
merge, may satisfy the separate trusted post-merge automatic build gate.
"""
import argparse

from verify_merged_pass import Hold, render_brain_verdict


def main() -> int:
    parser = argparse.ArgumentParser(description="Print an exact four-line Brain receipt; no GitHub writes")
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--decision", choices=("PASS", "HOLD"), required=True)
    args = parser.parse_args()
    try:
        print(render_brain_verdict(args.pr, args.head_sha, args.base_sha, approve=args.decision == "PASS"))
    except Hold as err:
        parser.error(str(err))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
