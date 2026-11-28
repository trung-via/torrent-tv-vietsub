# G2.1 — minimal Owner integration slice

Core #200 and selected-release handoff/play #199 are merged. This candidate
extracts G2 private request submission/claim/receipt and native primitives
from exact #195 a6bd7882054b2d942809502c34c25c5b9c682cd1. No new worker, process,
scheduler or launcher. The existing Owner must call these seams; the G1
runtime itself is still not on main.

- owner_g2_support.py: same native browser listener/settings and AGY personal
  account preflight/alias logic; fixed G2-native error prefix rather than G1
  acquisition exception. No effects on import. Use the existing profile.
- owner_g2_inbox.py: same request IDs, paths, durable claim, exact selection
  binding and cleanup-only handoff recovery; trace callback reuses Owner log.
- owner_g2_submit.py: only publishes existing inbox from interactive Owner.
- Existing runtime composition: call bind_owner_g2(factory, runner) only where
  TTV_G2_WARM is enabled. From the existing Owner loop after G1 polling, call
  poll_owner_g2_idle(active=active, factory=trusted_v3_factory,
  owner_root=private_root, cache_root=cache_root,
  submit=lambda work: active.add(pool.submit(work)),
  handoff=publish_library_receipt, emit=emit, trace=owner_full_trace).
  Resolve publish_library_receipt from canonical poc/p2-source (no duplicate
  implementation). Keep one runner, one lock, same browser.pending namespace.
  Existing #195 runtime already has equivalent integrated hooks; no change to
  the installed files is implied. When reconciling G1 source, reuse the
  extracted primitives instead of maintaining duplicate implementations.

Offline tests exercise previous native lifecycle with mock CDP and provider,
claim/receipt, cleanup-only result reuse, shared lock and G1 priority, and the
actual #199 handoff with fake TorrServer transport. No AGY or TV calls.
No claim of new uninterrupted production acceptance. Existing Owner deployment
remains pinned to its prior approved installed delta. Full G1 runtime source
and final composition/packaging migration remain separate.
