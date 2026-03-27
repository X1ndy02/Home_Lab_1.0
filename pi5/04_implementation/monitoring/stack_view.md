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
- currently keeps admin credentials in compose, which is a known weak point

`renderer`

- supports dashboard image rendering
- extends Grafana output options without changing the scrape path itself

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

