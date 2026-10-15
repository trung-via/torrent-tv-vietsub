# TorrServer interface contract — DISCOVERY REQUIRED

Dependency: upstream https://github.com/YouROK/TorrServer; no fork or included binary in this initial repo.

## Proposed adapter methods

- `checkConnection(endpoint, auth?) -> Health | TypedError`
- `listTorrents() -> List<TorrentSummary> | TypedError`
- `listVideoFiles(torrentId) -> List<VideoFile> | TypedError`
- `resolvePlayableUrl(torrentId, fileId) -> StreamHandle | TypedError`

Exact paths, verbs, authorization and response schemas **MUST** be recorded against a pinned, deployed TorrServer release; example routes `/echo`, `/torrents`, `/stream`, `/play` are unverified. Do not hardcode undocumented assumptions as acceptance evidence.

## Test taxonomy

`SERVER_OFFLINE`, `SERVER_TIMEOUT`, `AUTH_REQUIRED`, `API_INCOMPATIBLE`, `NO_METADATA`, `NO_PEERS`, `HTTP_RANGE_UNSUPPORTED`, `MEDIA_UNSUPPORTED`, `SUBTITLE_UNSUPPORTED`.

Test mock offline/HTTP status/parser without Internet or BitTorrent. Real server smoke later using an authorized open-license fixture; record version and redacted request trace.
