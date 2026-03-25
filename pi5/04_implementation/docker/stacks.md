Stack View

Functional grouping

The Docker layer is split into three functional groups rather than one combined deployment:

- `nextcloud`: user-facing storage and collaboration path
- `monitoring`: observability and dashboarding path
- `home-assistant`: local automation and host-adjacent integration

That split keeps the application path separate from the system visibility path. If monitoring breaks, the storage stack can still run. If the storage stack breaks, the monitoring layer can still report on the host and surrounding services.

That grouping was a decision, not an accident. The main goal was to make failure domains easier to read on a single-node system where everything ultimately shares the same hardware.

Request and dependency flow

Storage path

The storage stack follows a standard dependency chain:

- client
- reverse proxy
- application service
- database
- cache

That means failures are not equal:

- if the proxy is down, outside access fails first
- if the application container is down, the service is effectively unavailable
- if the database is down, the application path may still answer but cannot behave correctly
- if the cache is down, the service may still function but with a degraded profile depending on workload

An antivirus sidecar exists beside the main path rather than directly inside it, which keeps that responsibility separated but adds one more moving part.

The important point is that health cannot be judged by one container being "up". This path only works properly when the entry layer, app logic, state layer, and supporting services all line up.

Monitoring path

The monitoring stack is intentionally simpler:

- host and exported metrics
- Prometheus collection
- Grafana visualisation
- renderer support for image output

This stack is operationally important, but not part of the primary user request path. Losing it hurts visibility, not core data flow.

That difference matters during failure analysis. A broken dashboard stack is serious, but it is a different class of failure from a broken storage path.

Home Assistant path

Home Assistant is kept separate because its integration model is different from the other stacks.

It needs closer access to the host environment, so practicality won over stricter network separation. That is useful for a home-lab automation role, but it is also the least clean isolation choice in the Docker layout.

That is a conscious compromise. The cleaner model would be stricter isolation. The chosen model is easier local integration.

Design choices that matter

- Separate compose projects reduce blast radius during routine changes.
- Persistent storage is attached from the host side so state survives container replacement.
- Monitoring is not bundled into the application stack, which keeps failures easier to classify.
- Reverse proxying is treated as the entry layer, not as an afterthought inside the app container.
- The control plane remains on the host because backup and shutdown behaviour are part of system design, not only app design.

What this still does badly

- Secrets are not handled well enough yet in the live stack.
- Some service health assumptions still depend on container uptime rather than stronger health modelling.
- The repo now reflects the shape of the deployment, but it does not yet capture every surrounding runtime detail in one place.
- Single-node design means true isolation is limited by the host itself, no matter how neat the compose layout looks.
