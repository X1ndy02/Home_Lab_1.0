Service Model

Host and service boundary
The monitoring path is split between Docker services and host-side logic.

That matters because the dashboards and metric collection run in containers, while some checks, timers, and notifications still depend on the host itself.

Inside Docker

- Prometheus handles metric collection
- Grafana handles dashboard visualisation
- renderer supports rendered output
- node-exporter exposes host metrics into the stack

Outside Docker

- systemd timers and cron jobs drive some regular checks and reports
- custom alert logic sends email notifications
- host storage provides the configuration, dashboards, and textfile metric inputs used by the monitoring stack

Data source model
This setup currently combines two monitoring styles:

- metric scraping through Prometheus and node-exporter
- host-side checks for events such as SSH activity, certificates, SMART health, and power conditions

That split is useful on a small system, but it means monitoring behaviour is not controlled from one place yet.

Failure model
The monitoring path can fail in different ways:

- if node-exporter breaks, host metrics disappear first
- if Prometheus breaks, dashboards and metric history lose freshness
- if Grafana breaks, visualisation disappears even if metrics are still being collected
- if host-side alert scripts drift, some important events may stop producing mail even while dashboards still look healthy

The important point is that dashboard availability and alert coverage are not the same thing in this design.

