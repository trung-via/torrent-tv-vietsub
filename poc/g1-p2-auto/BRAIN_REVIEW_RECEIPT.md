# Exact Brain review receipt before merge — G1+P2 private Debug automation

Purpose: prevent an approved source PR from being merged without the **machine-readable Owner Brain PASS** that the trusted post-merge build gate requires.

## Correct order

1. Independently review the current PR, its exact current **HEAD** SHA, current **main/base** SHA, changed files, applicable permissions and GitHub Actions checks. This source-only review does **not** attest real Redmi or release.
2. Use the read-only receipt renderer to avoid free-form formatting mistakes:

   ```sh
   python3 poc/g1-p2-auto/render_brain_verdict.py --pr NUMBER \
     --head-sha EXACT_40_HEX_HEAD --base-sha EXACT_40_HEX_MAIN_SHA --decision PASS
   ```

3. **Only after actual Brain PASS**, post the renderer output as an OWNER-authored GitHub PR issue comment, **exactly four lines, with no explanatory text, Markdown fence or header**:

   ```text
   TORRENT_TV_BRAIN_REVIEW_PASS_V1
   pr=NUMBER
   head_sha=EXACT_40_HEX_HEAD
   base_sha=EXACT_40_HEX_MAIN_SHA
   ```

   To revoke, independently post `--decision HOLD` output as the latest canonical comment before merge.
4. Re-fetch the comment and verify it is parsed by `canonical()` (not merely visible); check the latest HEAD/base and **completed successful PR CI** again before merging.
5. Merge only under the repository-specific standing authorization (Issue #42). The trusted main-push workflow independently verifies Owner association, exact four-line shape, timestamps **before merge**, PR identity/head/base, CI, and first-parent main; on mismatch it **HOLDs without entering the Windows runner**.

**Important:** `TORRENT_TV_BRAIN_REVIEW_V1` with a long narrative and `DECISION=PASS...` is a useful human report but **not** the canonical receipt. The validator now reports `BRAIN_VERDICT_NONCANONICAL_FOUR_LINE_REQUIRED` to distinguish that mistake from a genuinely missing review; **it still never accepts a free-form review as permission**. Do not edit/backdate/post a PASS after merge to revive a failed push event.

## Scope boundary

This change neither enables manual public-APK publishing nor grants ADB/TV permissions. The actual compiled Debug APK stays in the dedicated Windows runner's private vault; PUBLIC GitHub Actions receives redacted evidence only. Build-success does not mean TV-installed or G1/P2 E2E PASS.
