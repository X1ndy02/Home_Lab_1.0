Software

This system runs Debian 13 (trixie).

All major services run inside Docker containers.
Docker and Docker Compose v2 are used for orchestration.

Containers are organised into custom bridge networks to separate
application services from monitoring services.


Nextcloud stack

The core service is Nextcloud, running in multiple containers:

- Application container (Nextcloud + Apache)
- Database container (MariaDB)
- Cache container (Redis)
- Reverse proxy container (Nginx)
- Antivirus container (ClamAV)

All containers use an automatic restart policy.

If the application container crashes, Docker attempts a restart.



Storage
Application data and database data are stored on persistent host-mounted directories.
Monitoring services use separate persistent directories.
ClamAV uses a dedicated Docker volume.


Scheduled tasks
Nextcloud background jobs run every 5 minutes via cron.
Additional scheduled tasks include:
- System monitoring checks
- Backup execution
- Disk health testing
- Periodic system health summaries


Backups
Backups are handled using Restic.
The system performs full filesystem backups with system path exclusions.
Backups are:
- Encrypted
- Snapshot-based
- Retention-limited (4 for now)
- Scheduled via systemd timer

Snapshots are stored on dedicated local storage (sata ssd)


Monitoring
Prometheus collects host metrics via node-exporter.
Grafana provides dashboard visualisation.
Alerting is handled by a custom monitoring script which triggers
email notifications

Monitoring covers:
- Resource usage
- Disk health
- Service availability
- Certificate expiration
- Security-related events
- Power events


Security controls
Fail2Ban is active with multiple jails enabled.
SSH access is enabled.
Container services are isolated via Docker networking.
Reverse proxy handles TLS termination.


Simply said this system is designed (for now) for experimentation and operational learning.
