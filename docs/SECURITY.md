# Security and legal policy

- PRIVATE GitHub repository by default, no credentials/passkeys/magnets/private IP in source or test logs.
- Network trusted LAN only. No router forwarding, UPnP, Internet WAN exposure or firewall change without Human approval.
- HTTP Basic on cleartext LAN does not encrypt credentials; evaluate HTTPS/reverse proxy if credentials are used or if expanding deployment.
- Version pin, verify upstream artifact and licenses before distributing; do NOT vendor TorrServer executable initially.
- Do not ingest illegal catalog sources, scrape unauthorized services, bypass DRM, or distribute copyright-protected test movies.
- Use self-generated/open-license test fixture with provenance.
- Redact logs/screenshots; secrets must never be checked in, including `.env` and server credentials.
