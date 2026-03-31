# Repo Scripts

## SMTP Archive

Use [smtp_archive.py](smtp_archive.py) to store a sent mail copy inside `pi5/03_reports/03_reports/`, then optionally commit and push the archive update.

Example report mail:

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

Example alert mail:

```sh
python3 scripts/smtp_archive.py \
  --repo . \
  --source fail2ban_ban_alert \
  --timestamp 2026-03-26T23:06:18+11:00 \
  --from-addr alerts@example.invalid \
  --to-addr you@example.invalid \
  --subject "[Fail2Ban] sshd: banned 10.244.10.1 from rootnode" \
  --body-file /tmp/email.txt \
  --push
```

If GitHub HTTPS auth is not already configured, export `GITHUB_TOKEN` before using `--push`.
