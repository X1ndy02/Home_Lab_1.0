Service Model

Host and service boundary

Portainer runs entirely inside Docker, but it operates above the other stacks.
It has no application-level dependency on Nextcloud, monitoring, or Home Assistant.

Inside Docker

- one container: `portainer`
- one named volume: `portainer_data` (stores Portainer's own database and settings)
- Docker socket mounted read-write from the host

Outside Docker

- nothing — all Portainer logic stays inside the container
- the host-side compose file lives at `/home/xindy/portainer/docker-compose.yml`

Socket model

Portainer connects to `/var/run/docker.sock` to read and control the Docker runtime.
This gives it full visibility into all containers, images, volumes, and networks on the host.

That means:
- if the Docker daemon is healthy, Portainer can see and act on everything
- if the Docker daemon is down, Portainer loses its management capability even if its own container is still running
- Portainer's own container is managed by Docker, so a full Docker daemon restart will also restart Portainer

Failure model

- if the Portainer container exits, the management UI goes offline but all other stacks continue running normally
- if `portainer_data` is lost, Portainer settings and environment configuration are lost, but it can be re-initialised without affecting any other service
- Portainer is not in any critical path — losing it only affects the management UI, not service delivery
