# Pi 5 Implementation Exports

This directory is reserved for sanitized copies of the live Raspberry Pi 5 implementation.

Each subdirectory contains the relevant files for one subsystem: a README, service model, config references, and a link to the issues file in `../05_issues/`.

- `docker/` — container runtime model and stack layout
- `nextcloud/` — Nextcloud stack (app, db, redis, clamav, proxy)
- `monitoring/` — Prometheus, Grafana, node-exporter, renderer
- `portainer/` — Portainer CE container management UI
- `fail2ban/` — Fail2Ban jails and alert integration
- `restic/` — backup scheduling, retention, and notifications
- `ssh/` — SSH server configuration
- `smart/` — SMART disk health tests and monitoring
- `x120x_ups/` — Geekworm X120x UPS HAT daemons and shutdown sequence
- `home_assistant/` — Home Assistant container (host networking)
- `tor/` — not implemented; folder reserved

Secrets, passwords, tokens, and machine-specific private keys should not be committed.
