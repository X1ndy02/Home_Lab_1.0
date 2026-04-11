Service Model

Container roles

| Container | Image | Role |
|-----------|-------|------|
| `nextcloud-proxy` | nginx:alpine | TLS termination, HTTP→HTTPS redirect, reverse proxy |
| `nextcloud` | nextcloud:29-apache | Application logic, PHP, file handling |
| `nextcloud-db` | mariadb:11.4 | Persistent application database |
| `nextcloud-redis` | redis:7-alpine | Session cache and file locking |
| `nextcloud-clamav` | mkodockx/docker-clamav:latest | Antivirus scanning sidecar |

All containers use `restart: unless-stopped`.
No health checks are defined — container uptime is the only signal available without manual inspection.

Storage model

Persistent state is split across NVMe (application files) and SATA SSD (user data):

| Path | Device | Contents |
|------|--------|----------|
| `/srv/nextcloud/app` | NVMe | Nextcloud application files (PHP, config, apps) |
| `/mnt/backup/nextcloud/data` | SATA SSD | User data directory (symlinked from `/srv/nextcloud/app/data`) |
| `/srv/nextcloud/db` | NVMe | MariaDB data directory |
| `/srv/nextcloud/redis` | NVMe | Redis persistence |
| `/srv/nextcloud/certs` | NVMe | TLS certificate and key (self-signed with local CA) |
| `/srv/nextcloud/nginx` | NVMe | nginx config and access/error logs |
| `/srv/nextcloud/clamav` | NVMe | `clamd.conf` and `freshclam.conf` (mounted read-only) |

User data lives on the SATA SSD (`/dev/sda2`, mounted at `/mnt/backup`).
`/srv/nextcloud/app/data` is a symlink to `/mnt/backup/nextcloud/data`.
The SATA path is also bind-mounted directly into the container so the symlink resolves inside the Docker namespace.
ClamAV virus definitions are stored in a named Docker volume (`clamav-db`) rather than a bind mount.
All bind-mounted paths are covered by the Restic backup.

TLS model

nginx terminates TLS using a self-signed certificate generated with a local CA.
The certificate files are at `/srv/nextcloud/certs/nextcloud.crt` and `.key`.
HTTP (port 80) is redirected to HTTPS (port 443) at the nginx layer.
`client_max_body_size` is set to 2 GiB, matching the PHP upload limit of 1024 MB with headroom.

The self-signed certificate will show browser warnings on any device that has not imported `nextcloud-ca.crt`.

Trusted domains

Configured trusted domains:
- `localhost`
- `192.168.1.181` (LAN IP)
- `10.244.10.4` (ZeroTier primary IP)
- `10.244.10.244` (ZeroTier secondary IP)

If the Pi's LAN IP changes, Nextcloud will reject requests from the new address until the config is updated.

Antivirus model

ClamAV listens on TCP port 3310 (internal to the Docker network) and a local Unix socket.
The `files_antivirus` Nextcloud app (v5.6.7) connects to ClamAV and scans files on upload.
Scan limits: max file size 200 MiB, max scan time 120 seconds.
A separate `clamav-mirror` systemd service on the host keeps virus definitions up to date independently of the container.

Failure model

- if the proxy container stops, all access to Nextcloud is lost — it is the single entry point
- if the app container stops, the service is unavailable even if the proxy is still running
- if MariaDB stops, the app may still respond to cached requests briefly but cannot write or authenticate correctly
- if Redis stops, file locking and session caching degrade — the app continues but performance and reliability drop
- if ClamAV stops, upload scanning fails — depending on Nextcloud's antivirus configuration, uploads may be blocked or pass through unscanned
- container uptime is the only monitored health signal — a container that is running but deadlocked looks healthy to Docker
