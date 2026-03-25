# Docker Implementation

This directory captures the live Docker implementation currently running on the Raspberry Pi 5.

## Runtime summary

- Engine: Docker 26.1.5
- Compose: Docker Compose v2.26.1
- Docker root: `/var/lib/docker`
- Storage driver: `overlay2`
- Cgroup driver: `systemd`
- Logging driver: `json-file`
- Service manager: `systemd` via `docker.service`

## Active compose projects

| Project | Source path | Containers | Network mode |
|---|---|---:|---|
| `nextcloud` | `/srv/nextcloud/docker-compose.yml` | 5 | bridge (`nextcloud_default`) |
| `monitoring` | `/srv/monitoring/docker-compose.yml` | 4 | bridge (`monitoring_default`) |
| `home-assistant` | `/home/xindy/RaspPi5_Home_Lab/home-assistant/docker-compose.yml` | 1 | host |

## Running containers

| Container | Image | Project | Service |
|---|---|---|---|
| `nextcloud-db-1` | `mariadb:11.4` | `nextcloud` | `db` |
| `nextcloud-redis-1` | `redis:7-alpine` | `nextcloud` | `redis` |
| `nextcloud-clamav-1` | `mkodockx/docker-clamav:latest` | `nextcloud` | `clamav` |
| `nextcloud-app-1` | `nextcloud:29-apache` | `nextcloud` | `app` |
| `nextcloud-proxy-1` | `nginx:alpine` | `nextcloud` | `proxy` |
| `monitoring-prometheus-1` | `prom/prometheus:latest` | `monitoring` | `prometheus` |
| `monitoring-node-exporter-1` | `prom/node-exporter:latest` | `monitoring` | `node-exporter` |
| `monitoring-grafana-1` | `grafana/grafana-oss:latest` | `monitoring` | `grafana` |
| `monitoring-renderer-1` | `grafana/grafana-image-renderer:latest` | `monitoring` | `renderer` |
| `homeassistant` | `ghcr.io/home-assistant/home-assistant:stable` | `home-assistant` | `homeassistant` |

## Files in this directory

- `engine.md` describes the host-level Docker service configuration.
- `stacks.md` summarizes the three compose stacks and their storage layout.
- `compose/` contains sanitized copies of the live compose files and selected safe config snapshots.

## Sensitive values

Sensitive values are not committed here.

The live system currently stores secrets in places that should eventually be cleaned up:

- `/srv/nextcloud/.env` contains database and admin credentials.
- `/srv/monitoring/docker-compose.yml` currently hard-codes the Grafana admin password.
- `/srv/monitoring/grafana/api.key` and `/srv/monitoring/grafana/admin.password` exist on disk and are intentionally excluded.

The copies in this repo are redacted templates, not raw secrets.
