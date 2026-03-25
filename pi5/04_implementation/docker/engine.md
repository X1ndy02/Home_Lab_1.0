# Runtime Model

## Host and container boundary

The host is still the real control plane.

Docker is used for long-running application services, but the machine-level concerns remain outside the containers:

- backup scheduling
- service supervision
- UPS shutdown handling
- security tooling
- system monitoring logic

That split is deliberate. If the host loses power, needs shutdown coordination, or has to inspect service state, it should not depend on the application containers being healthy first.

## Isolation model

The runtime is a middle ground between convenience and separation:

- application stacks are separated into distinct compose projects
- most services use bridge networking
- persistence is externalised onto host-backed storage
- restart behaviour is handled by the container runtime rather than custom wrapper scripts

This is enough isolation for a small lab environment without turning the Pi into a maze of one-off service management logic.

## Persistence model

Stateful services are designed around persistent storage outside ephemeral container layers.

That matters for three reasons:

1. backups target stable host paths
2. data can be inspected without rebuilding containers
3. recovery does not depend on preserving a container filesystem

Docker-managed volumes are used where they make sense, but most important state is intentionally visible from the host side.

## Recovery model

Ordinary failures are expected to be handled by restart policies and compose-managed service grouping.

More serious recovery paths rely on the host:

- the host can stop or start the runtime cleanly
- backup tooling operates independently of the application stacks
- power-loss handling can shut services down in a controlled way

That separation is more useful on a small always-on system than pushing every operational concern into containers.

## Why not a heavier model

I did not use full virtualisation for this layer because the goal here was service isolation with low overhead, not hypervisor-style separation.

For this hardware, containerisation is the practical point on the curve:

- easier to iterate on
- cheaper in resource use
- good enough for the current risk level

If the lab grows into multiple nodes or more exposed services, this part should probably become stricter.
