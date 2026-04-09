Portainer CE Implementation

System view

- standalone Docker management UI
- connects to the local Docker socket directly
- provides a web interface for inspecting and managing all containers, stacks, volumes, and images
- runs as a single container with a persistent named volume for its own state
- installed 2026-04-09, image pinned to version 2.39.1

Portainer sits above the application stacks rather than inside any of them.
It does not participate in the Nextcloud, monitoring, or Home Assistant dependency chains.
Its only dependency is access to `/var/run/docker.sock` on the host.

What interacts with what

- Portainer reads the Docker socket to discover and manage all running containers
- all stacks (nextcloud, monitoring, home-assistant) are visible through Portainer
- state is persisted in a named Docker volume (`portainer_data`)
- admin credentials are set at startup via bcrypt hash passed as a command argument

Access

- local network: `http://192.168.1.181:9000`
- ZeroTier VPN: `http://10.244.10.4:9000`
- HTTPS: `https://192.168.1.181:9443` / `https://10.244.10.4:9443`

Why this design

- keeping Portainer in its own standalone compose project means it can be restarted or updated without touching any application stack
- the Docker socket mount is the simplest integration model for a single-node host
- no edge agent or remote agent is used because the host is the same machine Portainer runs on

Flow

- Portainer container starts and binds to the Docker socket
- admin login uses a bcrypt-hashed password set in the compose command argument
- all local Docker environments are visible under the local environment in the UI

Trade-offs

- socket access gives Portainer full control over the Docker runtime, which is a privileged position
- this is acceptable for a single-user lab, but it would need more restriction in a shared environment
- the edge agent approach was tested first but discarded — it added complexity with no benefit on a single-node host

What is here

- [service_model.md](service_model.md): host/container boundary
- [issues_and_improvements.md](issues_and_improvements.md): known gaps and next steps
- compose file: `../docker/compose/portainer/docker-compose.yml`
