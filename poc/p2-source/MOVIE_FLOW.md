# Flow 3 — standalone movie playback

One approved private movie request -> existing AGY worker -> exact selected release
-> existing Owner handoff -> TorrServer Library -> existing paired runner -> OMP.
No Vietsub opt-in, no Android modifications, no extra worker or service.
The private request play flag is explicit. The existing submit helper is the ingress;
owner_movie_flow.ps1 waits for the exact ready receipt, then invokes play once.
A one-shot launch claim preserves uncertain effects. Never replay a search/add/launch
without reconciliation. An ACK/foreground is an operational receipt, not a playback PASS.
TrackTimecode=false forces server history timecode to zero; history is optional resume
information, not an acceptance gate. Actual playback requires direct observed evidence.
Preserve existing G1 manual request and all earlier subtitle behavior.
Training: compare observed search latency, source-bound selected identity and optional
metadata; no exhaustive search or extra AGY turn. No locator supplied to AGY. No
new TV launch or torrent addition during discovery-only training.
Baseline: Sintel actual AGY 60488 ms, Owner add/readback 5234 ms, playback verified by
Human after single ACK; recovered phases, not continuous latency. See Issue #191.
Candidate only; exact-head review and installed Owner acceptance remain separate.
