Issues And Improvements

Real issues already found
Secret handling is weaker than it should be
The live setup still has secret sprawl:

- one stack stores sensitive values in an env file
- the monitoring stack currently keeps the Grafana admin password directly in its compose definition
- monitoring-related secret material exists on disk outside this repo and is intentionally not committed

Shutdown behaviour still needs tightening
UPS shutdown validation already exposed one container-management problem: during a low-battery shutdown test, `nextcloud-clamav-1` needed forced termination instead of exiting cleanly within the normal stop window.

Its not catastrophic, but it is exactly the kind of detail that matters once the lab is supposed to behave like a real always-on service host.

Repo coverage is still incomplete
Home Assistant is running as part of the Docker layer, but its wider configuration still lives outside the main `pi5` tree. The repo is moving in the right direction, but it is not yet a full clean export of the whole container environment.

Trade-offs accepted for now
- preferred simpler container orchestration over a heavier platform
- accepted some host dependency in exchange for easier maintenance
- kept the stacks understandable before making them highly abstract
- accepted that a single-node Pi cannot provide the same failure isolation as a distributed or virtualised design
