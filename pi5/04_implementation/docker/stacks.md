# Compose Stack Summary

## Nextcloud

Source path:
- `/srv/nextcloud/docker-compose.yml`

Services:
- `db` (`mariadb:11.4`)
- `redis` (`redis:7-alpine`)
- `clamav` (`mkodockx/docker-clamav:latest`)
- `app` (`nextcloud:29-apache`)
- `proxy` (`nginx:alpine`)

Persistent paths:
- `/srv/nextcloud/db`
- `/srv/nextcloud/redis`
- `/srv/nextcloud/app`
- `/srv/nextcloud/nginx`
- `/srv/nextcloud/certs`
- Docker volume `nextcloud_clamav-db`

Ports exposed on host:
- `80/tcp`
- `443/tcp`

Notes:
- Uses `.env` for database and Nextcloud admin credentials.
- Reverse proxy terminates TLS and forwards traffic to the `app` container.

## Monitoring

Source path:
- `/srv/monitoring/docker-compose.yml`

Services:
- `prometheus` (`prom/prometheus:latest`)
- `node-exporter` (`prom/node-exporter:latest`)
- `grafana` (`grafana/grafana-oss:latest`)
- `renderer` (`grafana/grafana-image-renderer:latest`)

Persistent paths:
- `/srv/monitoring/prometheus`
- `/srv/monitoring/grafana`
- `/srv/monitoring/metrics/textfile`

Ports exposed on host:
- `3000/tcp`
- `8081/tcp`
- `9090/tcp`
- `9100/tcp`

Notes:
- Grafana admin credentials are currently defined directly in the live compose file and should be moved to an env file or secret mechanism.
- Prometheus currently scrapes only `node-exporter`.

## Home Assistant

Source path:
- `/home/xindy/RaspPi5_Home_Lab/home-assistant/docker-compose.yml`

Services:
- `homeassistant` (`ghcr.io/home-assistant/home-assistant:stable`)

Persistent paths:
- `/home/xindy/RaspPi5_Home_Lab/home-assistant/config`

Network mode:
- `host`

Notes:
- Uses the host timezone `Australia/Sydney`.
- Home Assistant configuration is currently kept outside this repo's `pi5` tree and should be migrated later if you want full repo coverage.
