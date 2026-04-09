Home Assistant Implementation

System view

- Home Assistant running as a single Docker container
- uses host networking so it can discover and communicate with local devices directly
- image: `ghcr.io/home-assistant/home-assistant:stable`
- timezone set to `Australia/Sydney`
- configuration stored at the live path in `/home/xindy/RaspPi5_Home_Lab/home-assistant/config/`
- compose file managed from `/home/xindy/RaspPi5_Home_Lab/home-assistant/`

Home Assistant sits separate from the other application stacks.
It uses host networking rather than a bridge network because device discovery (mDNS, SSDP, Bluetooth) does not work correctly through Docker's bridge NAT.

What interacts with what

- Home Assistant reads and writes its own config from the host-mounted config path
- host networking gives it direct access to the LAN for device discovery
- the Pi Monitor pushes host metrics into Home Assistant via a cron-driven script (`update_pi_host_metrics.sh`) every minute
- no reverse proxy sits in front of it — it is accessed directly on its port from the LAN or ZeroTier

Why this design

- host networking is the standard approach for Home Assistant in Docker and avoids mDNS and discovery issues
- keeping it in a separate compose project from the other stacks means it can be restarted independently
- config lives in `RaspPi5_Home_Lab/` rather than this repo because it contains device tokens, integration credentials, and automation rules that are not sanitised for commit

Trade-offs

- `stable` tag is not pinned to a specific version — updates happen on the next `docker compose pull`
- configuration is not in this repo — it lives in a separate repository and is not backed up by Restic in a structured way
- host networking reduces isolation compared to bridge networking
- no health check is defined

What is here

- [service_model.md](service_model.md): host networking model, config path, failure implications
- [issues_and_improvements.md](../../05_issues/home_assistant.md): known gaps and next steps
- compose file: `../docker/compose/home_assistant/docker-compose.yml`
