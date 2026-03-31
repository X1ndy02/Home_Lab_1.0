Archive Automation

System view

- `scripts/smtp_archive.py` is the explicit archive path when the sender already knows the mail type
- `scripts/smtp_capture_push.py` is the automatic path when a raw RFC822 mail copy is available
- both scripts write into `pi5/03_reports/03_reports/` and can commit and push the result

Detection model

- explicit mode uses a fixed source ID such as `grafana_weekly` or `fail2ban_ban_alert`
- automatic mode reads the subject and content, then maps the mail into a known report or alert folder
- if automatic detection does not match a known pattern, it falls back to `misc_report` or `misc_alert`

Archive model

- reports are written under `01_system_reports/`
- alerts are written under `02_system_alerts/`
- report mail is stored as one run folder with `email.txt` and copied attachments
- alert mail without attachments is stored as one timestamped `.txt` file inside a monthly bucket
- alert mail with attachments is stored as one timestamped folder

This keeps repeated summaries separate from one-off incidents while still preserving the mail body and the files that were sent with it.

Push model

- `--push` commits only the archived files and pushes the current `HEAD`
- HTTPS push can use `GITHUB_TOKEN` or `SMTP_ARCHIVE_GITHUB_TOKEN`

Example flow

Weekly Grafana report

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

Automatic capture from a raw mail

```sh
python3 scripts/smtp_capture_push.py \
  --repo . \
  --email-file /tmp/message.eml \
  --push
```
