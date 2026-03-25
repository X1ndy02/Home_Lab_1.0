Runtime Model
Host and container boundary
The host is still the real control plane.

Docker is used for long-running application services, but the machine-level concerns remain outside the containers:
- backup scheduling
- service supervision
- UPS shutdown handling
- security tooling
- system monitoring logic

That split is intentionalbecouse in case when host loses power, needs shutdown coordination, or has to inspect service state, it should not depend on the application containers being healthy first

The key decision here was not letting orchestration convenience replace operational control. The host stays above the stacks, not buried within them

Isolation model
- application stacks are separated into distinct compose projects
- most services use bridge networking
- persistence is externalised onto hostbacked storage (hard storage sata ssd)
- restart behaviour is handled by the container runtime instead of custom scripts
This is enough isolation for a small lab environment without turning the Pi into a maze

On a small ARM-based always-on machine, every extra layer has a cost. The runtime had to stay simple enough to operate without building a private platform just to run a few services...

Persistence model
Stateful services are designed around persistent storage outside container layers.
That matters for these three reasons:
1. backups target stable host paths (If a container dies, the recovery path should still be obvious from the host)
2. data can be inspected without rebuilding containers
3. recovery does not depend on preserving a container filesystem..

Recovery model
Ordinary failures are expected to be handled by restart policies and compose-managed service grouping

More serious recovery paths rely on the host:
- the host can stop or start the runtime cleanly
- backup tooling operates independently of the application stacks
- power-loss handling can shut services down in a controlled way (only when ups stat is 20% or less)
this separation is more useful on a small always-on system than pushing every operational concern into containers

Test result; 
During UPS shutdown validation, one container did not exit cleanly inside the normal stop window. That is exactly the kind of problem that would be harder to reason about if recovery logic lived inside the same service layer that was failing...

Why not a heavier model
I did not use full virtualisation for this layer because the goal here was service isolation with low overhead, not hypervisor style separation

If the lab grows into multiple nodes or more exposed services, this part should probably become stricter.
