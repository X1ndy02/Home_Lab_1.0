Service Model

Host and service boundary

Restic runs entirely on the host, not inside Docker.

That matters because:
- Docker stacks depend on the host, not the other way around
- a backup tool that runs inside a container would depend on that container being healthy before it could protect anything
- keeping restic on the host means it can still run even if one or more application stacks are degraded

The backup script, systemd timer, and restic binary all live on the host.
The only Docker-adjacent part is that application data written inside containers is persisted to host-mounted paths, which means restic can reach it directly without container-level coordination.

Backup model

Source: `/` (full filesystem)
Exclusions: `/proc`, `/sys`, `/dev`, `/run`, `/tmp`, `/mnt/backup`, `/mnt`, `/media`, `/lost+found`

The exclusion list removes virtual filesystems, temporary paths, and the backup target itself.
What remains is the full application state: Docker bind-mount paths under `/srv`, system config, scripts, and user data.

Restic uses content-defined chunking and deduplication.
That means unchanged blocks are not re-stored on each run, which keeps the per-snapshot size increment small even though each snapshot covers the full filesystem.

Retention model

Keep-last: 4 snapshots
Prune: runs on every successful backup

Current snapshot sizes are approximately 47–48 GiB per snapshot.
Pruning runs immediately after backup rather than on a separate schedule, which keeps the repository state consistent after each run.

Storage model

Repository location: `/mnt/backup/restic` on the SATA SSD at `/mnt/backup`
The SATA SSD is physically separate from the NVMe boot drive.
The mount is checked before every backup run — if the device is not mounted, the script exits early and sends a failure alert rather than silently writing to the wrong path.

Notification model

Every backup run sends an email with:
- overall result (SUCCESS or FAILED)
- run counts (successes, failures, warnings)
- last run details (start time, files processed, snapshot ID, disk usage)
- log file attached

A secondary disk-pressure warning is sent if usage on `/mnt/backup` reaches 80% after a successful run.
All outgoing email is archived to the GitHub repo using `smtp_archive.py`.

Failure model

- if the SATA SSD is not mounted, backup exits before touching restic and alerts
- if the restic command fails, a failure mail is sent with the full log attached
- if msmtp mail delivery fails, the notification is silently lost — there is no fallback delivery path
- if the git archive push fails, a separate alert is sent for that failure; the backup result itself is unaffected
- if the systemd timer drifts or is disabled, backups stop silently — there is no external watchdog checking timer health
