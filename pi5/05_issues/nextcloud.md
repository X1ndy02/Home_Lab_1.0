Issues And Improvements

Open issues

ClamAV image is unofficial and unmaintained upstream
`mkodockx/docker-clamav` is not the official ClamAV image.
The official image is now `clamav/clamav`.
Switching requires verifying that the config file paths and socket behaviour are compatible before replacing it.
This was deferred to avoid breaking a working antivirus integration.

No container health checks
None of the five containers have a `healthcheck` defined.
Docker reports them as healthy if they are running, regardless of whether the application inside is actually responding.
A deadlocked app container or a MariaDB instance that accepted the start but cannot serve queries would both appear healthy.

Self-signed certificate causes browser warnings
Any device accessing Nextcloud for the first time sees a browser security warning unless it has imported `nextcloud-ca.crt`.
A certificate from a trusted CA (e.g. via Let's Encrypt with a local DNS challenge) would remove this friction.
This is a trade-off accepted for now because Nextcloud is not internet-exposed.

Trusted domains use hardcoded IPs
If the Pi's LAN IP changes (DHCP reassignment), the trusted domains list must be updated manually or Nextcloud will reject requests.
Using a local hostname or static DHCP reservation would make this more stable.

ClamAV definitions volume is not covered by Restic
The `clamav-db` named volume is not a bind mount and is not in the Restic backup path.
If the volume is lost, definitions are re-downloaded on startup, but this could take time and leave uploads unscanned during recovery.

Nextcloud 29 is end-of-life
Version 29 reached end-of-life in mid-2025. The current stable release is 31.x.
No security patches are being issued for v29. Upgrade path: 29 → 30 → 31 (two sequential upgrades required).

Resolved

Cron background jobs were broken (fixed 2026-04-12)
`/etc/cron.d/nextcloud` referenced container name `nextcloud-app-1` but the container is named `nextcloud`.
All background tasks (file indexing, version pruning, AV queue, quota updates) were silently failing.
Fixed by correcting the container name in both cron entries.

ZeroTier primary IP missing from trusted domains (fixed 2026-04-12)
`10.244.10.4` (primary ZeroTier IP) was not in the trusted domains list.
Only the secondary IP `10.244.10.244` was listed.
Both IPs are now present.

Duplicate localhost in trusted domains (fixed 2026-04-12)
`localhost` appeared twice in the trusted domains array (indices 0 and 1).
Duplicate removed.

overwrite.cli.url pointed to http://localhost (fixed 2026-04-12)
CLI and cron commands generated incorrect URLs.
Updated to `https://192.168.1.181`.

No log rotation (fixed 2026-04-12)
`nextcloud.log` had grown to 64 MB with no rotation configured.
`log_rotate_size` set to 10 MB in config.php.

Brute force protection disabled (fixed 2026-04-12)
The `bruteforcesettings` app was installed but disabled.
App enabled.

No login anomaly detection (fixed 2026-04-12)
The `suspicious_login` app was installed but disabled.
App enabled.

User data on NVMe (moved to SATA 2026-04-12)
User data directory was stored on the NVMe alongside the application files.
Moved to SATA SSD at `/mnt/backup/nextcloud/data/`.
`/srv/nextcloud/app/data` is now a symlink to the SATA path.
The SATA path is bind-mounted directly into the container so Docker can resolve the symlink.

What I would change next

1. Upgrade Nextcloud from 29 to 31 (via 30) — v29 is end-of-life and unpatched.
2. Add Docker health checks for the app and database containers at minimum — a simple `php occ status` check for the app and a MariaDB ping for the database.
3. Replace `mkodockx/docker-clamav` with the official `clamav/clamav` image after verifying config compatibility.
4. Set a static DHCP reservation for the Pi to prevent the trusted domains issue from appearing after a router reboot.
5. Investigate a local DNS + Let's Encrypt setup to remove the self-signed certificate warning without exposing Nextcloud to the internet.
6. Review whether the ClamAV definitions volume should be converted to a bind mount so it is included in Restic backups.
