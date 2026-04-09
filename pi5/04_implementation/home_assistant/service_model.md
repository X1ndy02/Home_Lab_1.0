Service Model

Host and service boundary

Home Assistant runs inside Docker but uses host networking.

That means it shares the host's network stack directly — it binds to the host's IP addresses rather than a Docker bridge address.
This is required for mDNS, SSDP, and other local discovery protocols to work correctly.
The trade-off is reduced network isolation compared to bridge-networked containers.

Container model

| Property | Value |
|----------|-------|
| Image | `ghcr.io/home-assistant/home-assistant:stable` |
| Network | host |
| Restart | unless-stopped |
| Config mount | `./config:/config` (relative to compose file location) |
| Time sync | `/etc/localtime:/etc/localtime:ro` |

The compose file lives at `/home/xindy/RaspPi5_Home_Lab/home-assistant/docker-compose.yml`.
The config directory is at `/home/xindy/RaspPi5_Home_Lab/home-assistant/config/`.

Config model

Home Assistant's configuration, integrations, device tokens, and automation rules live in the config directory.
This is not committed to this repo because it contains credentials and machine-specific state.
It is managed in the separate `RaspPi5_Home_Lab` repository.

Metrics integration model

A cron job runs `update_pi_host_metrics.sh` every minute.
This pushes Pi host metrics (CPU, memory, temperature, disk) into Home Assistant via its REST API.
Home Assistant stores and displays these as sensors.

Failure model

- if the container stops, the Home Assistant UI and all automations go offline
- because it uses host networking, a container restart does not change its IP or port — clients reconnect automatically
- if the config directory is lost, all integrations, automations, and device configuration must be rebuilt
- the config directory is not currently included in the Restic backup path
- no health check is defined — container uptime is the only Docker-level signal
