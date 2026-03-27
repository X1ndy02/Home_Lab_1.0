# Repo Scripts

## SMTP Archive

Use [smtp_archive.py](smtp_archive.py) to store a sent mail copy inside `pi5/03_reports/03_smtp/`, then optionally commit and push the archive update.

Example recurring report:

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

Example event alert:

```sh
python3 scripts/smtp_archive.py \
  --repo . \
  --source ups_power_alert \
  --timestamp 2026-03-27T22:31:00+11:00 \
  --from-addr alerts@example.invalid \
  --to-addr you@example.invalid \
  --subject "[UPS] POWER EVENT · AC LOST" \
  --body-file /tmp/email.txt \
  --push
```

If GitHub HTTPS auth is not already configured, export `GITHUB_TOKEN` before using `--push`.
