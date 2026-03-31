Repo Scripts

SMTP archive

- `smtp_archive.py` stores a mail copy in the correct report or alert folder when the source is already known
- use it when a sender script can already tell whether the mail is backup, Grafana, Fail2Ban, UPS, or Pi monitor

Example

```sh
python3 scripts/smtp_archive.py \
  --repo . \
  --source pi_monitor_weekly \
  --timestamp 2026-03-27T22:30:00+11:00 \
  --from-addr alerts@example.invalid \
  --to-addr you@example.invalid \
  --subject "Weekly Pi Monitor Summary (2026-03-27)" \
  --body-file /tmp/email.txt \
  --attach /tmp/pi-monitor-summary.txt \
  --push
```

SMTP auto capture

- `smtp_capture_push.py` parses a raw mail copy, detects the report or alert type, extracts attachments, archives the result, and can push it straight away
- use it when the mail path can provide a full RFC822 message but does not already know the exact archive source ID

Example using a saved raw mail

```sh
python3 scripts/smtp_capture_push.py \
  --repo . \
  --email-file /tmp/mail.eml \
  --push
```

Example reading from stdin

```sh
python3 scripts/smtp_capture_push.py \
  --repo . \
  --stdin-email \
  --push < /tmp/mail.eml
```

Fallback behavior

- if automatic detection does not match a known subject or content pattern, the script falls back to `misc_reports` or `misc_alerts`

Push note

- if GitHub HTTPS auth is not already configured, export `GITHUB_TOKEN` before using `--push`
