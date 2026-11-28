# Flow 3 + Vietsub AI — Human decision 2026-11-28

DECIDED: explicit Brain/Human find-and-play request activates movie search →
TorrServer → native Redmi playback → existing Vietsub AI. Normal Library
playback and manual TV Bật Vietsub AI remain independent and unchanged.
No second Owner, translator, scheduler, P4 receiver or global auto-on.

- Private `TTV-OWNER-G2-CONCIERGE-V1` requires one authorized selected
  film and play=true. Old selection/metadata schemas do not authorize auto AI.
  Selected and Library receipts propagate auto_vietsub=true only for concierge,
  bound by the existing digest and request ID. Runner sends
  flow3Vietsub=request_id on existing authenticated /omp/launch. Existing
  launch attempt claim applies. Explicit concierge may replace current
  playback; legacy remote play keeps its no-interrupt behavior.
- OMP pin 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f. Apply TV overlay AFTER
  G1/G2/P4/P3 composition from #195 a6bd7882054b2d942809502c34c25c5b9c682cd1.
  Only paired Android remote events interpret flow3Vietsub, and the queue
  hash and exact file must match. The initial native VLC load consumes its
  ID once locally, then calls the same real request path as the TV button.
  Local navigation during metadata resolution wins; no automatic request
  on Next, seek, resume, manual Library selection or consumed ID. For
  concierge only, select VLC for the existing P4 receiver. P3/P4 exact
  session/hash/file, cancellation and translation checkpoint reuse remain
  unchanged; no synthetic P3 packets or independent subtitle worker.
- Owner package baseline b1ee5e177b9768d4a5e96a79ca4b22602236855f. Apply Owner
  overlay to staged bridge preserving unrelated G1 changes. Same pool,
  three G1 slots plus one G2 slot, independent active sets and poll exceptions.
  G2 lazily uses isolated CDP9556MovieProfile/loopback 9556 and
  cache_root/movie-discovery/.native-v13; G1 port 9555, lock and journals
  untouched. Unknown G2 browser effect can block G2 only. Real account
  quota/network/CPU limits may still affect both. Do not delete old markers.
- Dry-run the patcher on disposable sources:
  python poc/p2-source/flow3_dual_overlay.py --mode owner --source-root <staged OwnerBridge>
  python poc/p2-source/flow3_dual_overlay.py --mode tv --source-root <composed OMP>
  Add --apply only to verified disposable source tree, before compilation.
- SOURCE candidate only. Existing deployed package #202 remains historical.
  Next: verify complete actual composed Android build including this overlay,
  independently review, package exact Owner delta and obtain applicable
  Windows/Redmi deployment authority. No AGY/TV calls or install from this PR.
  No claim of uninterrupted native E2E or rendered Vietsub. Old stacked G1
  source still required for composition. First real acceptance should exercise
  explicit concierge and ordinary Library/manual independently, plus OFF
  or manual change during pending subtitle.
