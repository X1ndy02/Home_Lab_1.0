Restic Implementation

System view

- full filesystem backup running on the host, outside Docker
- backs up `/` with a fixed exclusion list
- stores snapshots on the local SATA SSD at `/mnt/backup/restic`
- retention is 30 snapshots (one month), pruned on each run
- after each local backup, a copy is pushed to Cloudflare R2 (offsite), keeping the last 2 snapshots there
- scheduled daily at 21:00 AEST via systemd timer
- sends two separate email notifications per run: one for local, one for R2
- sends push notification via ntfy on success, failure, and disk pressure

Restic is part of the operational control layer, not the application layer.
It runs independently of the Docker stacks so a broken container cannot prevent a backup from completing.

What interacts with what

- systemd timer triggers the backup script daily
- the script sources configuration from `/etc/restic/backup.env`
- backup reads from `/` with exclusions applied from `/etc/restic/excludes.txt`
- local repository lives at `/mnt/backup/restic` on the SATA SSD
- offsite repository lives in Cloudflare R2 bucket `rootnode-restic` (S3-compatible)
- on completion the script sends email via msmtp and archives the notification to the GitHub repo
- ntfy receives a push notification for every outcome (success low priority, warning high, failure urgent)
- if the backup mount is not present the script exits early and sends a failure alert

Why this design

- host-side placement means Docker failures cannot block backup execution
- backing up `/` rather than individual service paths is simpler and more complete for a single-node Pi
- SATA SSD as the primary backup target gives physical separation from the NVMe boot drive
- R2 as the offsite target removes the single point of failure — a lost Pi or SATA drive does not take the backup with it
- 30 local snapshots gives a full month of daily recovery points
- 2 R2 snapshots keeps cloud storage minimal while still providing a current offsite copy
- email notification on every run makes it easy to see if a backup silently stopped working
- separate local and R2 emails make it easier to tell exactly which part had a problem

Flow

Backup flow

- systemd timer fires at 21:00 AEST
- script checks that `/mnt/backup` is a live mount point — exits with alert if not
- restic backs up `/` using the exclusion file
- completed snapshot is retained, older snapshots beyond keep-last=30 are pruned
- script copies the new snapshot to Cloudflare R2
- R2 is pruned to keep-last=2 after each copy
- two separate emails are sent: one for local result, one for R2 result, each with its own log attached
- mail is archived to the GitHub repo via `smtp_archive.py`

Disk pressure flow

- after a successful local backup, disk usage on `/mnt/backup` is checked
- if usage reaches or exceeds 80%, a warning is added to the local email subject and an ntfy alert is sent

Failure flow

- if the mount is missing, the script exits before touching restic and sends a failure alert
- if the local restic backup command fails, the script sends a failure alert and exits — R2 copy does not run
- if the R2 copy or rotation fails, a separate failure email is sent for R2 only; the local success email is unaffected
- failure emails include a troubleshooting section; success emails do not
- if the git archive push fails, a separate mail is sent for that specific failure without blocking the backup result

Trade-offs

- backing up the full filesystem means snapshot size is large (~48 GiB logical, ~23 GiB actual stored with deduplication)
- 30 local snapshots give a full month recovery window but will grow storage gradually as the system changes
- R2 keeping only 2 snapshots minimises cloud cost but limits the offsite recovery window to 2 days
- no `restic check` is run after each backup — repository integrity is assumed rather than validated
- the systemd timer drives the schedule; if it drifts or is disabled, backups stop silently

What is here

- [restic-backup.sh](restic-backup.sh): live backup script (also at `/usr/local/sbin/restic-backup.sh`)
- [service_model.md](service_model.md): host boundary, backup and retention model, failure implications
- [issues_and_improvements.md](../../05_issues/restic.md): known gaps and next steps
- `config/`: sanitized reference copies of the environment and exclusion files
