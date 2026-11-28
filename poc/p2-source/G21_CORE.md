# G2.1 — extracted source core (not a new runtime)

Source provenance: #195 exact a6bd7882054b2d942809502c34c25c5b9c682cd1.
Reuse the existing AGY warm-session module and film discovery module at their
canonical Owner paths. Move runtime-only imports to the native call boundary;
missing Owner dependencies fail explicitly before creating a cache or starting
a browser/provider. No new launcher, service, worker, provider or browser.

Main includes G2.2/G2.3 via #199 (merge 910042514b4c86d50c2a4e712f0be386f9fbdb4c).
This slice brings the core, not the installed Owner wiring. Remaining native
dependencies: translator_gateway, agy_v13_native_producer (browser listener,
session settings, journal writer), Owner private ingress and shared browser lock,
runtime composition. They are not on main. Extract/reconcile those dependencies
without importing unrelated G1 behavior; keep one installed Owner. Do not
deploy this partial slice or claim end-to-end main readiness.

Synthetic tests are exercised by the existing P2-source CI; no provider,
TorrServer, Windows, or TV calls. Native selection evidence from Cosmos
(46094765906, 46095958040) and actual playback (46096210234, Human confirmation)
is historical; not a new native test or proof of this branch's full runtime.
