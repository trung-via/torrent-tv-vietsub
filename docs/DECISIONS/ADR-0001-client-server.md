# ADR-0001 — Windows/NAS server + native TV client

**Status:** ACCEPTED (Human selected option B, 2026-10-15).  
**Context:** TV hardware platform uncertain and torrent engine may overburden TV resources.  
**Decision:** Windows TorrServer is default streaming host; NAS optional; TV runs lightweight Android TV app only when firmware supports. Phone uses TorrServer existing web interface for adding torrents in P0.  
**Consequences:** PC/NAS must be powered on during viewing; seek/network/peer conditions must be surfaced; 4K/codec compatibility requires actual tests.  
**Rejected for MVP:** all-in-one torrent TV engine, native mobile companion, custom streaming backend/database, universal transcoding, auto-AI subtitles.
