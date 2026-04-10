Pi 5 Improvement Checklist

Current checklist

- ~~Review secret handling across Docker-related configs and move sensitive values out of compose files where possible.~~ Partially done 2026-04-09 — Grafana credentials moved to `.env`. Nextcloud secrets already in `.env`. Remaining: other stacks.
- Recheck shutdown behaviour for slow-exit containers and adjust stop timing if needed.
- Improve service health modelling so "container is running" is not treated as the same thing as "service is healthy".
- ~~Bring remaining Docker-related configuration under the same `pi5` repo structure.~~ Done 2026-04-09 — all active stacks now documented in `04_implementation/`.
- ~~Bring Nextcloud-related implementation details under the same repo structure in a cleaner way.~~ Done 2026-04-09 — Nextcloud has full implementation docs.
- ~~Bring Home Assistant-related configuration under the main Pi 5 repo structure.~~ Partially done 2026-04-09 — compose file and service docs added. Live config remains in `RaspPi5_Home_Lab/` repo and is not yet backed up by Restic.
- Repair or replace the screen stats script path now that the display side is broken.
- Improve monitoring for each Docker container instead of treating container uptime alone as enough signal.
- Make monitoring findings feed back into GitHub so important problems are documented and turned into issues when found.
- Rework weak areas in the Docker setup that still depend on rough secret handling and incomplete runtime visibility.
- ~~Document the current limits of the single-node design so isolation trade-offs stay explicit.~~ Done — trade-offs documented in each service's README and service_model.
- ~~Add a broader security hardening pass across SSH, Docker, exposed web services, and firewall rules.~~ Partially done 2026-04-10 — VNC and RDP disabled, HA and go2rtc restricted to ZeroTier via iptables. SSH still public pending key auth setup.
- Bring more of the web-facing jail behaviour into regular reporting, not only SSH.
- Add monitoring around Fail2Ban itself so jail failures or path drift become more visible.
- Review log path dependencies whenever Dockerized services or storage paths change.
- Keep the repo copy aligned with the live jail setup and custom action files.
- Add Home Assistant config directory to Restic backup coverage.
- ~~Pin Home Assistant image to a specific version tag.~~ Done 2026-04-10 — pinned to `2026.3.2`.
- ~~Add SMART tests and pi-monitor coverage for the NVMe boot drive.~~ Partially done 2026-04-10 — pi-monitor now checks NVMe health every cycle as a separate `SMART_NVME` check. Scheduled test timer not yet added.
- Set up SSH key authentication and disable password auth once keys are confirmed working.
- ~~Add an offsite or remote Restic backup target.~~ Done 2026-04-10 — Cloudflare R2 bucket `rootnode-restic` configured, snapshots copied nightly after local backup, keep-last=2 on R2.
