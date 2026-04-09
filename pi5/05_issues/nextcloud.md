Issues And Improvements

Real issues already visible

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

What I would change next

1. Add Docker health checks for the app and database containers at minimum — a simple `php occ status` check for the app and a MariaDB ping for the database.
2. Replace `mkodockx/docker-clamav` with the official `clamav/clamav` image after verifying config compatibility.
3. Set a static DHCP reservation for the Pi to prevent the trusted domains issue from appearing after a router reboot.
4. Investigate a local DNS + Let's Encrypt setup to remove the self-signed certificate warning without exposing Nextcloud to the internet.
5. Review whether the ClamAV definitions volume should be converted to a bind mount so it is included in Restic backups.
