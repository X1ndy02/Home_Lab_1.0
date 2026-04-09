Restic Implementation

System view

- full filesystem backup running on the host, outside Docker
- backs up `/` with a fixed exclusion list
- stores snapshots on the local SATA SSD at `/mnt/backup/restic`
- retention is kept to the last 4 snapshots and pruned on each run
- scheduled daily at 21:00 AEST via systemd timer
- sends email notification on success, failure, and disk pressure

Restic is part of the operational control layer, not the application layer.
It runs independently of the Docker stacks so a broken container cannot prevent a backup from completing.

What interacts with what

- systemd timer triggers the backup script daily
- the script sources configuration from `/etc/restic/backup.env`
- backup reads from `/` with exclusions applied from `/etc/restic/excludes.txt`
- repository lives at `/mnt/backup/restic` on the SATA SSD
- on completion the script sends email via msmtp and archives the notification to the GitHub repo
- if the backup mount is not present the script exits early and sends a failure alert

Why this design

- host-side placement means Docker failures cannot block backup execution
- backing up `/` rather than individual service paths is simpler and more complete for a single-node Pi
- SATA SSD as the backup target gives physical separation from the NVMe boot drive without requiring a network target
- keeping only 4 snapshots limits storage growth while still providing a short recovery window
- email notification on every run makes it easy to see if a backup silently stopped working

Flow

Backup flow

- systemd timer fires at 21:00 AEST
- script checks that `/mnt/backup` is a live mount point — exits with alert if not
- restic backs up `/` using the exclusion file
- completed snapshot is retained, older snapshots beyond keep-last=4 are pruned
- success or failure mail is sent with log attachments
- mail is archived to the GitHub repo via `smtp_archive.py`

Disk pressure flow

- after a successful backup, disk usage on `/mnt/backup` is checked
- if usage reaches or exceeds 80%, an additional warning mail is sent
- this is a second check rather than a blocking condition

Failure flow

- if the mount is missing, the script exits before touching restic and sends a failure alert
- if the restic backup command fails, the script sends a failure alert and exits non-zero
- if the git archive push fails, a separate mail is sent for that specific failure without blocking the backup result

Trade-offs

- backing up the full filesystem is simple, but it means the backup size is large (~48 GiB per snapshot)
- four snapshots give a short window of recovery — enough for detecting a silent failure, but not a long history
- local-only storage means a physical failure of the SATA SSD would take both the host and the backup target
- restic's deduplication reduces the stored size, but growth still happens as the system changes
- no remote or offsite copy exists yet

What is here

- [service_model.md](service_model.md): host boundary, backup and retention model, failure implications
- [issues_and_improvements.md](../../05_issues/restic.md): known gaps and next steps
- `config/`: sanitized reference copies of the environment and exclusion files
