Docker Implementation

This part of the lab is not meant to be a Docker tutorial. The point is to show how container runtime choices were used inside a small single-node Pi system, what role each stack plays, and where the design is still rough around the edges.

System view

- Single-node container host
- Services grouped by function rather than mixed into one large compose file
- Persistent application data kept outside containers
- Monitoring kept separate from application traffic
- One service uses host networking where direct local integration is more useful than strict network isolation

In practice the container layer is doing three jobs:

1. isolate services from each other
2. make updates and rebuilds easier
3. keep the host usable as the control plane for backup, monitoring, UPS handling, and recovery

What interacts with what

- client traffic reaches the proxy layer before it ever touches the storage application
- the storage application depends on both database and cache services, so app uptime alone does not mean the full service is healthy
- host metrics move into the monitoring stack, then into dashboards and alert outputs
- host-side backup and shutdown logic can act on the Docker runtime without depending on the containers to coordinate themselves

Why this design

- Containers were chosen instead of full virtual machines because the hardware is good enough for multiple services, but not a machine I want to burden with VM overhead.
- Service groups were split into separate stacks so failures are easier to reason about.
- Persistent bind mounts were preferred over keeping state only inside Docker-managed internals because backups, inspection, and recovery are simpler that way.
- The host remains the operational control layer because power events, backup runs, and service recovery need one place that stays above the application stacks.

This is a pragmatic layout, not a purity exercise. It trades some isolation for easier maintenance on a small system.

Constraints that shaped it

- single-node design, so separation has to come from service boundaries rather than host boundaries
- limited hardware overhead compared with a larger server, so the runtime model has to stay light
- always-on role, so shutdown and restart behaviour matters more than fast initial setup
- mixed workload, so monitoring and user-facing services cannot all be treated as equally critical

Flow

User-facing flow

- Client request reaches the reverse proxy layer
- Proxy forwards traffic to the application container
- Application container depends on database and cache services
- Persistent state is written to host-backed storage rather than ephemeral container layers

Monitoring flow

- Host and container-adjacent metrics are exposed to the monitoring stack
- Prometheus scrapes those metrics
- Grafana reads from Prometheus and provides dashboards and rendered output

Operational flow

- Containers run under a `systemd`-managed Docker service
- Restart policies handle ordinary process exits
- Host-level backup, UPS, and monitoring logic stay outside Docker so they can still act on the stacks during degraded conditions

This matters because the host can still stop, back up, or inspect the runtime even when the application path is unhealthy.

Trade-offs

- Containers are lighter than VMs, but they do not give the same isolation boundary.
- Bind mounts make recovery easier, but they also mean host filesystem layout matters more.
- Separate compose projects improve clarity, but they spread configuration across multiple places.
- Host networking for Home Assistant is practical, but it is a weaker separation model than bridge networking.

What makes this believable is not that it looks tidy. It is that the design already shows pressure from real operational concerns: secret sprawl, shutdown sequencing, and the fact that some containers behave very differently once the host is under stress.

What is here

- [engine.md](engine.md): runtime model and host/container boundary
- [stacks.md](stacks.md): service grouping, dependency paths, and failure implications
- [issues_and_improvements.md](issues_and_improvements.md): real problems found so far and what should be cleaned up next
- `compose/`: sanitized reference copies of the current stack definitions

The compose files are reference material, not the main story. The important part is the system shape and the decisions behind it.
