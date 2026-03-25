Security Controls

Fail2Ban is active and configured with multiple jails:

- sshd
- nextcloud
- nginx-http-auth
- nginx-botsearch
- recidive

The configuration monitors authentication failures and suspicious patterns
across SSH and web services.

Behavior model

- Repeated failed authentication attempts trigger temporary IP bans.
- The recidive jail increases ban duration for repeat offenders.
- Web authentication abuse is monitored separately from SSH.
- All security-related events are logged and included in monitoring alerts.

SSH access is enabled.

Reverse proxy handles TLS termination.

Monitoring includes detection of:
- Multiple failed SSH attempts
- New IP login attempts
- Unexpected service interruption

Security in this system is defensive and reactive.
There is no external Web Application Firewall or IDS in place.


Backup Strategy

Backups are handled by Restic.

Backup model

- Full filesystem snapshot
- System paths excluded
- Snapshot-based design
- Encrypted repository
- Retention limited to 4 snapshots
- Scheduled daily via systemd timer

Storage location

- Snapshots currently stored on dedicated local SATA SSD
- No off-site backup configured yet

Planned expansion

- Periodic copy to secondary local system
- Additional cloud copy

Reporting

Each backup run generates a status email:

- SUCCESS
- FAILED
- WARNING (disk usage >= 80%)

Each report includes:

- Execution summary
- Full backup log
- Any warning events detected

Restore testing

- No documented restore validation cycle currently in place
