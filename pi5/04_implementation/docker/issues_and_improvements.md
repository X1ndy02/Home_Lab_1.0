Issues And Improvements

Real issues already found

Secret handling is weaker than it should be

The live setup still has secret sprawl:

- one stack stores sensitive values in an env file
- the monitoring stack currently keeps the Grafana admin password directly in its compose definition
- monitoring-related secret material exists on disk outside this repo and is intentionally not committed

That is workable for a lab, but not a good long-term pattern.

This is also a design weakness, not just a cleanup item. Secret placement affects how safely the system can be rebuilt, reviewed, or shared.

Shutdown behaviour still needs tightening

UPS shutdown validation already exposed one container-management problem: during a low-battery shutdown test, `nextcloud-clamav-1` needed forced termination instead of exiting cleanly within the normal stop window.

That is not catastrophic, but it is exactly the kind of detail that matters once the lab is supposed to behave like a real always-on service host.

It shows a real interaction problem between application behaviour and host-level shutdown handling. That kind of issue is more useful evidence than a clean compose file because it proves the stack has been exercised under stress.

Repo coverage is still incomplete

Home Assistant is running as part of the Docker layer, but its wider configuration still lives outside the main `pi5` tree. The repo is moving in the right direction, but it is not yet a full clean export of the whole container environment.

That gap matters because design reasoning is easier to trust when the repo covers the operational context around the containers, not only the stack files themselves.

Trade-offs accepted for now

- preferred simpler container orchestration over a heavier platform
- accepted some host dependency in exchange for easier maintenance
- kept the stacks understandable before making them highly abstract
- accepted that a single-node Pi cannot provide the same failure isolation as a distributed or virtualised design

That trade-off is fine at this stage, but only if the weak spots are documented honestly.

What I would change next

1. Move live secrets out of compose definitions and into a cleaner secret or env-file strategy.
2. Revisit shutdown ordering and stop timeouts for stateful or slow-exit containers.
3. Add better health modelling so service quality is not judged only by whether a container process still exists.
4. Bring the remaining Docker-related configuration under the same repository structure.
