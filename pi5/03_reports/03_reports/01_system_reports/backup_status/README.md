# Backup Status

Source: `/usr/local/sbin/restic-backup.sh`

Schedule: daily via `restic-backup.timer` at `21:00`

This folder is for backup result emails. They are reports, not alerts, because they summarize a run and can include attached logs.

Subject patterns:

- `Backup SUCCESS`
- `Backup FAILED`
- `Backup WARNING: disk usage ...`

Recommended path shape:

- `YYYY-MM-DD/2026-03-30T21-01-25_backup_success/`
- `YYYY-MM-DD/2026-03-30T21-01-25_backup_success/email.txt`
- `YYYY-MM-DD/2026-03-30T21-01-25_backup_success/restic-backup.log`

Relevant code

- timer: `/etc/systemd/system/restic-backup.timer`
- service: `/etc/systemd/system/restic-backup.service`
- script: `/usr/local/sbin/restic-backup.sh`

```ini
[Timer]
OnCalendar=*-*-* 21:00:00
```

```sh
send_mail "Backup SUCCESS (keep-last=$RESTIC_KEEP_LAST)" "$(summary_counts "$RESTIC_LOG")" "$RESTIC_LOG"
send_mail "Backup WARNING: disk usage ${usage_pct}%" "$(summary_counts "$RESTIC_LOG")" "$RESTIC_LOG"
```
