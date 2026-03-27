# SMTP Archive Automation

This section documents how SMTP report copies are written into the repo and pushed to GitHub.

## Script

The archive entry point is:

- `scripts/smtp_archive.py`

It does four jobs:

1. map a mail source to the correct `03_smtp` folder
2. write a copy of the sent mail as `email.txt` or a timestamped alert file
3. copy attachments or a whole report directory into the same archive entry
4. `git add`, `git commit`, and optionally `git push`

## Source Mapping

Current supported source IDs:

- `pi_monitor_weekly`
- `pi_monitor_monthly`
- `grafana_weekly`
- `grafana_monthly`
- `smart_weekly`
- `fail2ban_monthly`
- `ups_monthly`
- `pi_monitor_alert`
- `ups_power_alert`
- `ups_shutdown_alert`
- `partition_health_alert`

Relevant code:

```python
SOURCES = {
    "pi_monitor_weekly": {
        "kind": "recurring",
        "base": "pi5/03_reports/03_smtp/recurring/pi_monitor_weekly",
        "run_dir": "{date}",
    },
    "ups_power_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_smtp/alerts/ups_power",
    },
}
```

## Archive Rules

Recurring sources write into a dated run folder:

- `pi5/03_reports/03_smtp/recurring/<source>/<date-or-month>/email.txt`

Alert sources write into a monthly bucket:

- `pi5/03_reports/03_smtp/alerts/<source>/YYYY-MM/YYYY-MM-DDTHH-MM-SS_subject.txt`

Relevant code:

```python
if cfg["kind"] == "recurring":
    target_dir = base / run_dir
    email_path = target_dir / "email.txt"
else:
    month_dir = base / dt.strftime("%Y-%m")
    email_path = month_dir / f"{stamp}_{slug}.txt"
```

## Push Behavior

If `--push` is used, the script commits only the archived files and then pushes the current `HEAD` to the configured branch.

If HTTPS credentials are not already stored, the script can use:

- `GITHUB_TOKEN`
- `SMTP_ARCHIVE_GITHUB_TOKEN`

Relevant code:

```python
token = os.environ.get("GITHUB_TOKEN") or os.environ.get("SMTP_ARCHIVE_GITHUB_TOKEN")
...
run(["git", "commit", "-m", commit_msg], cwd=repo_root)
run(["git", "push", push_target, f"HEAD:{push_branch}"], cwd=repo_root)
```

## Example Commands

Recurring report with attachments:

```sh
python3 scripts/smtp_archive.py \
  --repo . \
  --source grafana_weekly \
  --timestamp 2026-03-27T20:00:00+11:00 \
  --from-addr alerts@example.invalid \
  --to-addr you@example.invalid \
  --subject "[Pi Weekly Report] 2026-03-27" \
  --body-file /srv/monitoring/reports/weekly-2026-03-27/report.txt \
  --attach-dir /srv/monitoring/reports/weekly-2026-03-27 \
  --push
```

Event alert:

```sh
python3 scripts/smtp_archive.py \
  --repo . \
  --source ups_power_alert \
  --timestamp 2026-03-27T22:31:00+11:00 \
  --from-addr alerts@example.invalid \
  --to-addr you@example.invalid \
  --subject "[UPS] POWER EVENT · AC LOST" \
  --body-file /tmp/ups-mail.txt \
  --push
```

## Live Integration Pattern

For shell-based senders, call the archiver after the mail body and attachments already exist:

```sh
python3 /path/to/repo/scripts/smtp_archive.py \
  --repo /path/to/repo \
  --source grafana_weekly \
  --timestamp "$(date -Is)" \
  --from-addr "$FROM_ADDR" \
  --to-addr "$TO_EMAIL" \
  --subject "[Pi Weekly Report] $week_end" \
  --body-file "$OUT_DIR/report.txt" \
  --attach-dir "$OUT_DIR" \
  --push
```

For Python-based senders, use `subprocess.run([...], check=True)` after the email body string is written to a temp file.

