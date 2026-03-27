# SMTP Report Archive

This tree is reserved for copies of reports and alerts that were actually sent through the live mail path.

It is intentionally split by report type instead of by subsystem overview. The goal is to keep scheduled summaries separate from event-driven alerts so the archive matches how the mails arrive in practice.

Rules for this section:

- store only mail-originated copies here
- keep filenames date-based and predictable
- keep attachments beside the matching mail body
- sanitize anything that should not be public before commit

Recurring reports live under `recurring/`.
Event-driven alert copies live under `alerts/`.

Each subfolder should document:

- the live script that generates the mail
- the scheduler path if one exists
- a short code snippet showing the subject or dispatch path

Automation entry point:

- `scripts/smtp_archive.py`
- [automation.md](automation.md)

That script can:

- archive a sent mail copy into the correct folder
- copy attachments or a whole report directory
- commit only the archived files
- push to GitHub when `--push` is used
