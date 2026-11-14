# Torrent TV owner-session bridge — one-time enrollment, zero per-film prompts

Tracking: Issue #132. Draft source candidate stacked on automatic D2→P2
Draft #140. A GitHub PR does NOT install any process on Windows.

## Verified trust boundary

Dedicated GitHub Windows runner is NETWORK_SERVICE, nonadministrator,
Session 0, not the owner interactive identity:
- HostOps #43538220541: NETWORK_SERVICE, RUNNER_IS_ADMIN=FALSE.
- HostOps #43535767053: no owner EN cache or API key access.
- HostOps #43537417728: cannot register an interactive-owner task.

Never grant the shared NETWORK_SERVICE account local Administrators/full
profile access, bypass UAC, or copy subtitles/keys into PUBLIC GitHub.

## One owner process, no per-film Human action

One fixed Task Scheduler entry starts the PowerShell agent launcher at
logon under the actual owner Windows InteractiveToken, Limited privilege.
It decrypts owner-DPAPI key files in that account and starts the already
implemented D2→P2 AutomaticVietsubFlow with local cache/checkpoints and
Gemini 4 Hydrogen HIGH. One no-subtitle model GET at process startup,
not after each subtitle download.

Trusted OMP/TorrServer selected-media adapter calls
enqueue_selected_media(video_filename, owner_root=...) to enqueue an event
in owner-private LOCALAPPDATA. Owner agent consumes at most three events
per poll with an exclusive, persistent once-claim. The existing D2
confidence/SRT/one-POST/cache checks and P2 Gemini checkpoint/uncertain
retry rules run silently; D3/P4 TV binding remains downstream.

GitHub runner may optionally write only an eight-byte inert WAKE_V1
marker in a narrowly ACL-protected ProgramData Wake folder. A signal
cannot supply a movie name, command, API key, source file or TV identity.
Owner agent never executes marker contents and polls its owner-private
inbox independently. This is not generic remote command execution.

## One-time interactive owner enrollment

From a reviewed, exact-commit local checkout under the SAME Windows
account that owns the subtitle cache, run once:

    pwsh -NoProfile -File poc/p2-sub-discovery/install-owner-session-bridge.ps1

Installer refuses GitHub Actions, service identities, Session 0 and a
different user from the logged-in interactive desktop. It copies only
P2/D2 Python modules and a fixed PowerShell launcher into owner-private
LOCALAPPDATA, restricts directory ACLs, prompts once for currently
missing OpenSubtitles and Gemini keys, and stores them using owner DPAPI.
Subsequent film selections/logons require no password or approval prompts.
It registers and starts only the fixed limited interactive-logon task
TorrentTV-Vietsub-OwnerAgent, refusing to overwrite an unrelated task.

For optional GitHub WAKE signaling, the OWNER ADMIN may enroll once:

    pwsh -NoProfile -File poc/p2-sub-discovery/configure-runner-wake-acl.ps1

This requires normal interactive owner Administrator/UAC, and grants
NETWORK_SERVICE only CreateFiles in the inert ProgramData Wake folder,
plus file-only WriteData. No privilege to owner profile/keys/other folders.
If normal Windows task enrollment fails, an authorized owner must handle
the required Windows privilege through standard account/UAC controls.
HostOps cannot self-elevate.

## Status and honest evidence boundaries

- SOURCE_ONLY: implemented private event queue, DPAPI launcher, scheduled
  task installer and fixed HostOps WAKE sender, owner account separation.
- MOCK/CI: synthetic test one-off/blocked events, repeated startup, no
  user prompt, no queued command injection, malformed input and symlink
  refusal. Must cite exact CI once completed.
- REAL WINDOWS OWNER-SESSION SETUP: NOT_RUN until one-time install.
- OMP SELECTED-MEDIA EVENT ADAPTER: NOT_WIRED to live deployed player yet.
- REAL GEMINI API/REDMI P4 AUTOMATIC RECEIVER: NOT_RUN.
- GitHub runner remains NETWORK_SERVICE; no permission granted so far.

If OMP has not delivered a verified selected-video event into the owner
inbox, the agent has no work. Do not claim actual end-to-end automation
from merely creating the Draft PR or running offline unit tests.

## Rollback

Stop/unregister only TorrentTV-Vietsub-OwnerAgent under the owner account
and remove the installed bridge only after preserving owner-private cache
and checkpoints. Do not delete uncertain download/model claims merely
to trigger duplicate quota spend. Leave TorrServer/OMP and firewall alone.


## P3 playback trigger composition — exact source, no duplicate policy

This branch includes exact P3 trigger policy source from Draft #142 as a
source-preserving merge commit; the installer copies that module into
the owner-local app tree. The trusted_playback_to_owner.py adapter fetches
a FRESH current TV playback snapshot through a REQUIRED owner-trusted
function, applies the existing P3 ActivationDeduplicator, and enqueues
only DISPATCH decisions in the owner's private inbox. It does NOT accept
arbitrary GitHub JSON or script commands as a playback event.

P3 policy's attested=True is a scoped CALLER assertion, not cryptographic
authentication by itself. The actual Redmi OMP PlayRequest event subscriber
and TV/TorrServer auth source still must be implemented separately. This
candidate does NOT claim an installed real OMP event subscriber.

Owner-private P3 events use V2 with an opaque source fingerprint computed
from selected server + torrent hash + file index; older private V1 filename
events remain supported. The existing D2/P2 flow now keys its private
source cache by the verified opaque fingerprint for P3-bound events,
rather than reusing identical video filenames from different torrents.
The fingerprint is NOT an authenticated P4 TV media key.

The owner agent singleton uses an OS-held Windows lock, automatically
released on process exit or crash, so stale PID files no longer require
manual deletion. Existing D2 one-POST claims and P2 Gemini inflight
checkpoints deliberately REMAIN persistent, blocking ambiguous paid retries.

## Remaining actual deployment gate

GitHub's runner is built-in NETWORK_SERVICE in Session 0 and cannot enroll
a scheduled task under the logged-in owner's interactive account. A
reviewed one-time OWNER-session installation is necessary before the
agent runs. Inert GitHub WAKE cannot substitute for a verified OMP selection,
grant privileges, supply model secrets or authorize arbitrary commands.
Live provider/Redmi acceptance remains NOT_RUN.
