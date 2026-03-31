System Mail Archive

System view

- keeps repo copies of emails that were actually sent by the live Pi
- stores both plain mail bodies and attachments such as Grafana PNGs or log files
- separates report-style mail from alert-style mail so the archive matches what the operator receives

This section is not for general notes or hand-written reports. It is only for mail copies that came from the running system.

What interacts with what

- `01_system_reports/` stores scheduled summaries and run-result emails
- `02_system_alerts/` stores incident, warning, and state-change emails
- `scripts/smtp_archive.py` writes explicitly mapped mail into the correct folder
- `scripts/smtp_capture_push.py` parses raw RFC822 mail, detects the type, and archives it automatically

Why this design

- mail is already the operational output for this lab, so copying that output into the repo preserves what was actually seen
- keeping attachments beside the body makes Grafana and log-heavy mails easier to review later
- splitting by content keeps monthly reports away from one-off security or power events

Rules

- store only mail-originated copies here
- keep attachments beside the matching mail body copy
- keep names date-based and predictable
- sanitize anything that should not be public before commit

What is here

- `01_system_reports/`: scheduled summaries and backup result mail
- `02_system_alerts/`: security, power, storage, and network alert mail
- [automation.md](automation.md): how the archive and push flow works
