Stack View

Components

`node-exporter`

- exposes host metrics to Prometheus
- reads from mounted host paths such as `/proc`, `/sys`, and `/`
- also exposes host-generated textfile metrics through `/srv/monitoring/metrics/textfile`

`Prometheus`

- scrapes metrics every 30 seconds
- currently has a simple static scrape configuration
- acts as the data source for Grafana

`Grafana`

- provides dashboards for host and service visibility
- stores data and provisioning material on host-mounted paths
- admin credentials are stored in `/srv/monitoring/.env` and referenced by compose
- port 3000 is bound to the ZeroTier interface only (`10.244.10.4:3000`) — not exposed on the LAN

`renderer`

- supports dashboard image rendering
- extends Grafana output options without changing the scrape path itself
- runs on the internal bridge network only — no host port exposed

Network isolation
Prometheus, node-exporter, and renderer have no host port bindings.
All inter-service communication happens on an internal bridge network.
Only Grafana is reachable from outside containers, and only via ZeroTier.

Image versions (pinned 2026-04-09)
- `prom/prometheus:v3.9.1`
- `prom/node-exporter:v1.10.2`
- `grafana/grafana-oss:12.3.1`

How they interact

The monitoring path is intentionally short:

- node-exporter exposes host-side metrics
- Prometheus collects them
- Grafana queries Prometheus
- renderer supports image output for Grafana

What is not inside this stack

- the custom email alert logic is not represented in this compose project
- power-event handling is not represented in this compose project
- some security and certificate checks are still driven from host-side scripts and timers

That means this folder captures the dashboarding and metrics stack, but not the full alert pipeline yet.

