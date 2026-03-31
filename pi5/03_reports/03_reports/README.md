# System Mail Archive

This tree is for repo copies of emails that were actually sent by the live Pi.

It is split by content, not by service name:

- `01_system_reports/` for scheduled summaries and run-result emails
- `02_system_alerts/` for incident, warning, and state-change emails

Rules for this section:

- store only mail-originated copies here
- keep attachments beside the matching mail body copy
- keep names date-based and predictable
- sanitize anything that should not be public before commit

Each subfolder documents:

- the live sender
- the schedule or trigger
- the expected subject pattern
- a short code snippet showing how the mail is produced

Automation entry point:

- `scripts/smtp_archive.py`
- [automation.md](automation.md)
