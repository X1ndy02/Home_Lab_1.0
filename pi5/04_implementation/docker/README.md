Docker Implementation

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
- client traffic firstly reaches the proxy layer adn then it ever touches the storage application
- the storage application depends on both database and cache services
- host metrics move into the monitoring stack, then into dashboards and alert outputs
- host-side backup and shutdown logic can act on the Docker runtime without depending on the containers to coordinate themselves

Why I chose this this design
- Containers were chosen instead of full VMs because the hardware is good enough for multiple services, but not a machine I want to burden with VMs (and buid something liek qubes OS i snearly imposible on PI5, with my current lvl)
- Service groups were split into separate stacks
- Persistent bind mounts were used instead of relying only on Docker’s internal storage, as they make backups, inspection, and recovery much easier
- The host remains the operational control layer because power events, backup runs, and service recovery need one place that stays above the whole application stacks

It trades some isolation for easier maintenance on my small system

Constraints that shaped it
- single-node design, so separation has to come from service boundaries rather than host boundaries
- limited hardware overhead compared with a larger server, so the runtime model has to stay light
- always-on role, so shutdown and restart behaviour matters more than fast initial setup

Flow
User facing flow
- Client request reaches the reverse proxy layer
- Proxy forwards traffic to the application container
- Application container depends on database and cache services
- Persistent state is written to host-backed storage instead of container layers

Monitoring flow
- Host and container metrics are exposed to the monitoring stack
- Prometheus scrapes those metrics
- Grafana reads from Prometheus and provides dashboards and rendered output

Operational flow
- Containers run under a `systemd`managed Docker service
- Restart policies handle ordinary process exits
- Host level backup, UPS, and monitoring logic stay outside Docker so they can still act on the stacks even during degraded conditions
(This matters because any host can still stop, back up, or inspect the runtime even when the application path is unhealthy)

Trade-offs
- Containers are lighter than VMs, but they do not give the same isolation boundary
- Bind mounts make recovery easier
- Separate compose projects improve clarity, but they spread configuration across multiple places

What is here
- [engine.md](engine.md): runtime model and host/container boundary
- [stacks.md](stacks.md): service grouping, dependency paths, and failure implications
- [issues_and_improvements.md](issues_and_improvements.md): real problems found so far and what should be cleaned up next
- `compose/`

