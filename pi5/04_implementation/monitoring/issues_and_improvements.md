Issues And Improvements

Real issues already visible

Split monitoring logic makes coverage harder to reason about
The current setup uses both a containerized metrics stack and host-side checks, timers, and mail alerts. That is practical, but it makes it harder to see monitoring as one coherent system.

Secret handling is weaker than it should be
The monitoring compose file still keeps the Grafana admin password directly in the environment section. That is workable for a lab, but it should not remain the long-term pattern.

Container health visibility is still shallow
The current documentation already notes that container monitoring is mostly based on whether a container is up or exited. That is weaker than real service-health visibility.

Independent validation is limited
Because this is a single-node system, the monitoring stack depends on the same host it is observing. If the host fails hard, the observability path fails with it.

What I would change next

1. Move Grafana secrets out of compose and into a cleaner secret-handling path.
2. Bring more of the host-side alert scripts and timers into the repo under the `monitoring/` section.
3. Improve monitoring for individual services so health is not treated as equivalent to container uptime.
4. Add clearer validation of the monitoring stack itself so scrape failures, stale dashboards, or exporter drift become visible quickly.
5. Keep the documented monitoring layout aligned with the live Prometheus, Grafana, and alert-script setup.

