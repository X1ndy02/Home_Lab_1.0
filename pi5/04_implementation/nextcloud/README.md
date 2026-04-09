Nextcloud Implementation

System view

- Nextcloud 29.0.16 running as a multi-container Docker stack
- five containers: app, database, cache, antivirus, reverse proxy
- HTTPS only — HTTP redirects to HTTPS at the proxy layer
- self-signed TLS certificate with a local CA
- accessible on the LAN and via ZeroTier; not exposed to the public internet
- all persistent state stored in host-mounted directories under `/srv/nextcloud/`
- antivirus scanning enabled via the `files_antivirus` app (ClamAV)

What interacts with what

- client traffic enters through the nginx proxy on ports 80/443
- nginx terminates TLS and forwards to the app container on port 80 internally
- the app container reads from and writes to MariaDB for all application state
- Redis provides session cache and file locking to reduce database load
- ClamAV scans uploaded files via TCP socket on port 3310
- Fail2Ban watches the nginx logs for repeated authentication failures

Why this design

- separating proxy, app, database, cache, and antivirus into distinct containers keeps failure domains clearer
- nginx handles TLS at the entry point so the app container does not need to manage certificates
- Redis is required for proper file locking in Nextcloud — without it, concurrent access can cause conflicts
- ClamAV runs as a sidecar rather than inline so a scanner failure does not block the rest of the stack
- bind mounts under `/srv/nextcloud/` make backups, inspection, and recovery straightforward from the host

Flow

Request flow

- client connects to port 80 or 443 on the Pi
- nginx redirects HTTP to HTTPS
- nginx terminates TLS using the self-signed certificate
- request is proxied to the Nextcloud app container
- app reads session state from Redis and data from MariaDB
- responses return through the proxy to the client

Upload and scan flow

- file upload arrives at the app container via the proxy
- `files_antivirus` passes the file to ClamAV over TCP (port 3310)
- ClamAV returns a clean or infected result
- file is stored or rejected based on the scan result

Trade-offs

- self-signed certificate means browser warnings on any device that has not imported the local CA
- not internet-exposed keeps the attack surface small, but it means access from outside requires ZeroTier to be active
- ClamAV image (`mkodockx/docker-clamav`) is unofficial and not actively maintained upstream
- no container health checks are defined — container uptime is treated as equivalent to service health
- trusted domains are hardcoded IPs — if the Pi's LAN IP changes, access breaks until the config is updated

What is here

- [service_model.md](service_model.md): container roles, storage layout, TLS model, failure implications
- [issues_and_improvements.md](issues_and_improvements.md): known gaps and next steps
- compose file: `../docker/compose/nextcloud/docker-compose.yml`
