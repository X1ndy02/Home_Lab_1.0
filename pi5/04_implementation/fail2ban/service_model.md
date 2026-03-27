Service Model

Host and service boundary
Fail2Ban runs on the host, not inside the application containers.

That matters because it needs to see:
- system authentication events
- web-facing access failures
- repeated patterns across different services

Placing it on the host means it can observe both journal-based activity and log files written by containerized services without depending on those containers to provide their own protection layer.

Log source model
This setup is split across two kinds of sources:
- `sshd` uses the system journal
- Nextcloud and nginx jails use application log files
- recidive uses Fail2Ban's own log as an escalation source

Response model
The system is designed around short-window detection first, then longer-window escalation:
- base jails handle immediate repeated failures
- recidive catches repeat offenders over a much longer horizon
- email action makes the response visible to the operator

Notification model
The current setup sends ban notifications with extra management notes attached.

That is useful because the alert itself already contains:
- the jail involved
- the source IP
- relevant log lines
- quick commands for viewing or unbanning

It reduces the need to remember operational steps during routine cleanup
