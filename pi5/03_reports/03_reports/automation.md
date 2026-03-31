# SMTP Archive Automation

This section documents how sent mail copies land in `03_reports/` and are pushed to GitHub.

## Script

The archive entry point is `scripts/smtp_archive.py`.

It does four jobs:

1. map a mail source to the correct report or alert folder
2. write the mail copy as `email.txt` or a timestamped alert file
3. copy attachments or a whole report directory into the same archive entry
4. `git add`, `git commit`, and optionally `git push`

## Source Mapping

Current source IDs:

- `backup_status`
- `pi_monitor_weekly`
- `pi_monitor_monthly`
- `grafana_weekly`
- `grafana_monthly`
- `smart_weekly`
- `fail2ban_monthly`
- `ups_monthly`
- `pi_monitor_alert`
- `fail2ban_ban_alert`
- `partition_health_alert`
- `ups_power_alert`
- `ups_shutdown_alert`
- `network_failover_alert`

Reports are written under `01_system_reports/`.
Alerts are written under `02_system_alerts/`.

## Archive Rules

Report sources write into a run folder:

- `pi5/03_reports/03_reports/01_system_reports/<type>/<date-or-month>/email.txt`

Alert sources write into a monthly bucket:

- `pi5/03_reports/03_reports/02_system_alerts/<type>/YYYY-MM/YYYY-MM-DDTHH-MM-SS_subject.txt`

If a report source can send more than once in one day, the run folder includes a timestamped subfolder so mails do not overwrite each other.

## Push Behavior

If `--push` is used, the script commits only the archived files and then pushes the current `HEAD` to the configured branch.

If HTTPS credentials are not already stored, the script can use:

- `GITHUB_TOKEN`
- `SMTP_ARCHIVE_GITHUB_TOKEN`

## Example Commands

Weekly Grafana report with PNGs:

```sh
python3 scripts/smtp_archive.py \
  --repo . \
  --source grafana_weekly \
  --timestamp 2026-03-29T20:00:06+11:00 \
  --from-addr alerts@example.invalid \
  --to-addr you@example.invalid \
  --subject "[Pi Weekly Report] 2026-03-29" \
  --body-file /srv/monitoring/reports/weekly-2026-03-29/report.txt \
  --attach-dir /srv/monitoring/reports/weekly-2026-03-29 \
  --push
```

Fail2Ban ban alert:

```sh
python3 scripts/smtp_archive.py \
  --repo . \
  --source fail2ban_ban_alert \
  --timestamp 2026-03-26T23:06:18+11:00 \
  --from-addr alerts@example.invalid \
  --to-addr you@example.invalid \
  --subject "[Fail2Ban] sshd: banned 10.244.10.1 from rootnode" \
  --body-file /tmp/fail2ban-mail.txt \
  --push
```
