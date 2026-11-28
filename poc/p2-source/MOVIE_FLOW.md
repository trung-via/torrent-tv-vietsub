# Flow 3 — standalone selected release to playback (main-targeted slice)

Reuse existing Owner, TorrServer, HostOps and paired OMP. No extra service,
browser, worker, Android change, Vietsub activation or token transfer.

1. A trusted Owner-local producer supplies the authorized and matched selection
   as g2-<request_id>.selected.json. The model alone cannot grant rights.
2. owner_movie_handoff.py consumes that selection, performs at most one add,
   reads exact hash and file ID and publishes the ready receipt to the existing
   HostOps Receipts directory. Never guess a file or repeat uncertain add.
3. owner_movie_flow.ps1 waits for the same request's receipt then invokes
   owner_movie_play.ps1 once using the existing paired runner. The launch
   attempt is durable; HTTP ACK and PlayerActivity foreground are not rendering
   proof. TrackTimecode=false can produce zero history; history is not a gate.

The production checkpoint for Cosmos Laundromat was selected by AGY in
run 46094765906, independently read in 46095958040, recovered through the same
handoff and play scripts in 46096210234, and actual picture was confirmed
by Human on Redmi (Issue #191). AGY 55859 ms and Library recovery 5253 ms are
separate phases, not uninterrupted E2E latency. No second AGY call or play.
The actual Windows Owner G2.1 integration is still the stacked #195 candidate;
this main-targeted slice does not include or merge its G1 ancestors. It is
not standalone full production ingress. Exact-head CI and independent Brain
review under #42 remain separate. No new native run or deployment in this PR.
