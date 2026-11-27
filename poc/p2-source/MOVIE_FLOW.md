# Flow 3 - flat local handoff (candidate)

Reuse existing AGY Owner, TorrServer, HostOps and paired OMP. No additional
service, watcher, new browser, token transfer or public media payload.

1. A trusted Owner-local caller supplies an already authorized, matched
   selection as `g2-<request_id>.selected.json` in the Owner-private directory.
   Existing R5 metadata-only output cannot establish a release locator or rights;
   a trusted producer still has to supply this selection. Do not synthesize
   a locator from metadata or auto-grant authorization to model output.
2. The Owner invokes `python owner_movie_handoff.py <private_root> <request_id>`.
   This uses local TorrServer, publishes the private hash/file receipt into the
   already enrolled ProgramData HostOps Receipts directory, and emits a status
   only. A pending file selection never becomes a launch.
3. The existing paired runner invokes
   `pwsh -File owner_movie_play.ps1 -RequestId <request_id>` from the same
   pinned source. It reads the exact receipt, rechecks the selected file,
   reuses its own DPAPI token, and launches at most once. HTTP ACK is not
   playback proof. No owner credential or selected link crosses accounts.

The existing HostOps workflow must invoke these two steps for the same
authorized request. That operational invocation, ACL readback in the actual
account pair, AGY locator production, and session-bound Vietsub activation are
not yet verified or deployed. No new ACL, workflow or service is installed by
this source change. If an operation is uncertain, reconcile its saved evidence
rather than replaying the add or launch.
