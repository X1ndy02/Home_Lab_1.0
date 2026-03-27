Pi 5 Improvement Checklist

Current checklist

- Review secret handling across Docker-related configs and move sensitive values out of compose files where possible.
- Recheck shutdown behaviour for slow-exit containers and adjust stop timing if needed.
- Improve service health modelling so "container is running" is not treated as the same thing as "service is healthy".
- Bring remaining Docker-related configuration under the same `pi5` repo structure.
- Bring Nextcloud-related implementation details under the same repo structure in a cleaner way.
- Bring Home Assistant-related configuration under the main Pi 5 repo structure.
- Repair or replace the screen stats script path now that the display side is broken.
- Improve monitoring for each Docker container instead of treating container uptime alone as enough signal.
- Make monitoring findings feed back into GitHub so important problems are documented and turned into issues when found.
- Rework weak areas in the Docker setup that still depend on rough secret handling and incomplete runtime visibility.
- Document the current limits of the single-node design so isolation trade-offs stay explicit.
- Add a broader security hardening pass across SSH, Docker, exposed web services, and firewall rules so the lab improves beyond secret handling alone.
- Bring more of the web-facing jail behaviour into regular reporting, not only SSH.
- Add monitoring around Fail2Ban itself so jail failures or path drift become more visible.
- Review log path dependencies whenever Dockerized services or storage paths change.
- Keep the repo copy aligned with the live jail setup and custom action files.
