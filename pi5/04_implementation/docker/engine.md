# Docker Engine Notes

## Service

Docker is started by the distro-provided `docker.service` unit:

- Unit file: `/usr/lib/systemd/system/docker.service`
- Start command: `/usr/sbin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock $DOCKER_OPTS`
- Restart policy: `always`

There is currently no custom `/etc/docker/daemon.json` on this host.

## Host defaults observed on the Pi

- Docker root directory: `/var/lib/docker`
- Storage driver: `overlay2`
- Cgroup driver: `systemd`
- Logging driver: `json-file`

## Compose projects currently running

- `nextcloud`
- `monitoring`
- `home-assistant`

## Current Docker networks

- `bridge`
- `host`
- `none`
- `nextcloud_default`
- `monitoring_default`

## Current Docker volumes

- `nextcloud_clamav-db`
- one anonymous local volume present on the host

The application stacks primarily use bind mounts under `/srv` and the Home Assistant project directory.
