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

That is a simple design, but it creates one important dependency: if paths or logging behaviour drift, protection quality drops quickly.

Response model

The system is designed around short-window detection first, then longer-window escalation:

- base jails handle immediate repeated failures
- recidive catches repeat offenders over a much longer horizon
- email action makes the response visible to the operator

This is a reasonable middle ground for a small always-on host. It does not try to be clever. It tries to be dependable.

Notification model

The current setup sends ban notifications with extra management notes attached.

That is useful because the alert itself already contains:

- the jail involved
- the source IP
- relevant log lines
- quick commands for viewing or unbanning

It reduces the need to remember operational steps during routine cleanup.

Why not something heavier

I did not build a larger log-analysis pipeline around this part because the current system does not justify that complexity yet.

For this host, the better trade-off is:

- clear jails
- understandable ban logic
- visible notifications
- one small reporting loop

If the system grows in exposure or service count, this layer would probably need to become more centralized and less file-path-dependent.
