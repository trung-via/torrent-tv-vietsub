# Production fast dispatch (candidate)

Human decision 2026-11-28: Brain dispatches a clear production movie request immediately, without Library, CI, PR or installed hash prechecks. Existing Owner queue, not a new worker. The parameterized production command on #196 is:

`/tv-hostops movie 9e7f9b46af3863cfecf5c3786a58dede721bd12c search 2026 Public film title`

For already authorized media, use `play` instead of `search`. The current verified-media allowlist covers Big Buck Bunny (2008) and Cosmos Laundromat (2015); other titles cannot be promoted to play by setting an unverified rights flag. The read-only metadata path does not acquire a locator or add/play media. If source access is blocked, report the failure, do not bypass it. GitHub issue is public: do not send private media identifiers, credentials or links.

The source branch `hostops/production-movie` is pinned at 9e7f9b46af3863cfecf5c3786a58dede721bd12c. The fixed workflow admits only that branch pin and typed arguments. Existing trusted runner reads the comment data; existing HostOps dispatcher writes one durable input keyed by the authenticated comment ID, and existing Owner submitter claims the request. A rerun of the same comment cannot repeat its effects. Use the existing G2 selection/library receipt and paired OMP player, not a second orchestrator; only explicit play sets the session-bound auto-Vietsub flag. No G1 idle gate. Do not replay an unknown effect or clear a browser marker without reconciling the same request.

Source candidate only, not active until review/merge. The current failed Heart of the Beast request is metadata-only and ACCESS_BLOCKED, not a successful play. Its pending marker must be reconciled separately before further G2 execution. No new AGY call, TV launch or installation authorized by this change.
