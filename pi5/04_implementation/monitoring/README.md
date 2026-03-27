Monitoring Implementation

System view

- host and container observability layer
- keeps collection separate from the main application path
- combines Prometheus scraping, Grafana dashboards, and rendered output support
- still depends on host-side alert and timer logic outside Docker

In this lab, monitoring is not only a dashboard stack. It is part of the operational control layer that helps detect service failure, resource pressure, certificate drift, and security-relevant events before they turn into recovery work.

What interacts with what

- node-exporter exposes host metrics
- textfile metrics can be published from the host into node-exporter
- Prometheus scrapes exported metrics on a regular interval
- Grafana reads Prometheus data for dashboards and rendered views
- renderer supports image generation for dashboard output
- host-side alert scripts and timers still sit outside the container stack

Why this design

- keeping monitoring in its own stack makes failures easier to classify
- Prometheus and Grafana are simple enough for a single-node Pi lab
- host-backed storage keeps dashboards and config easier to inspect and recover
- host-side checks remain useful because some alerts are about the host itself, not only containers

This keeps observability close to the machine being protected without mixing it directly into the application stack.

Flow

Metrics flow

- host metrics are exposed by node-exporter
- Prometheus scrapes those metrics every 30 seconds
- Grafana queries Prometheus for dashboards
- renderer supports exported images when needed

Operational flow

- container uptime is managed by Docker restart policy
- dashboard state and provisioning stay on host-mounted paths
- alerting and summary logic still depend on host timers, scripts, and mail delivery

Trade-offs

- this is lighter than a larger monitoring platform, but it has fewer built-in alerting and correlation features
- separating dashboards from alert scripts keeps roles clearer, but it also splits monitoring logic across host and containers
- a single-node setup keeps maintenance simpler, but it cannot monitor itself from an independent failure domain

What is here

- [service_model.md](service_model.md): host/container boundary and how monitoring is split
- [stack_view.md](stack_view.md): the monitoring components and what each one does
- [issues_and_improvements.md](issues_and_improvements.md): weak spots and next cleanup items

