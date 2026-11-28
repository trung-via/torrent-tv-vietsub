# Flow 3 — exact Owner source overlay

The 10-file package snapshot is [b1ee5e177b9768d4a5e96a79ca4b22602236855f](https://github.com/trung-via/torrent-tv-vietsub/tree/b1ee5e177b9768d4a5e96a79ca4b22602236855f)
on `package/flow3-owner-20261128`, a distribution-only tree, not a merge
candidate. Its two runtime modules are generated from exact #195
`a6bd7882054b2d942809502c34c25c5b9c682cd1`; the other eight files come from merged #199/#200/#201
at `3ba642310c2191468a6aadfa1e73e1dc478b5e8d`. All ten blob IDs were read back from the package.
The old private bridge API stays compatible; the actual Owner loop now calls
the merged idle adapter, and the native factory uses the merged bind adapter
under the existing G2 opt-in. Existing G1/P3/P4 code is retained in the two
generated files, not merged as unrelated source into main.

To reproduce a source ZIP using a local repository that already contains the
three pinned Git objects (fetch explicitly beforehand if missing):

    python poc/p2-source/build_flow3_owner_overlay.py --repo . --output flow3-owner-source.zip

The builder validates exact input/output Git blob IDs, parses Python, compares
every output to the package snapshot, and writes a deterministic ZIP with
manifest. It neither fetches nor installs anything. CI tests the builder with
synthetic Git input; it does not execute actual runtime or the real package.
The package is a delta, not a complete fresh Owner install; existing enrolled
G1/P3/P4 dependencies, launcher, flags, task, profile, and private data are
required. Prior installed source may differ from #195, so this must not be
applied blindly. A future approved HostOps deployment must reconcile installed
bytes, preserve local G1 changes, back up affected files, and verify heartbeat.
No AGY, TV, Windows or provider operation is performed here.
