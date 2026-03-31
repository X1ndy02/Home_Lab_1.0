# UPS Reports

Source: `/usr/local/bin/x120x-ups-report.py`

Schedule: monthly via `x120x-ups-report.timer`

This folder is for report-style UPS mail. The live sender currently produces a monthly battery report built from `/var/log/x120x-ups-events.jsonl`.

Recommended path shape:

- `YYYY-MM/email.txt`

Relevant code

- timer: `/etc/systemd/system/x120x-ups-report.timer`
- service: `/etc/systemd/system/x120x-ups-report.service`
- script: `/usr/local/bin/x120x-ups-report.py`

```ini
[Timer]
OnCalendar=monthly
```

```python
subject = (
    f"{settings['subject_prefix']} Monthly battery report for {socket.gethostname()}"
    f" ({start_dt.strftime('%B %Y')})"
)
```
