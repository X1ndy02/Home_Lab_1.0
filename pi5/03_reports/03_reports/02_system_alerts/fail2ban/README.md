# Fail2Ban Alerts

Source: `/etc/fail2ban/action.d/sendmail-whois-lines-notes.conf`

Cadence: event-driven on ban actions

This folder is for security alert emails sent when a jail bans an IP. This is separate from the monthly Fail2Ban report because the content is an immediate incident notification.

Subject pattern:

- `[Fail2Ban] <jail>: banned <ip> from <fq-hostname>`

Recommended path shape:

- `YYYY-MM/2026-03-26T23-06-18_fail2ban_banned_10_244_10_1.txt`

Relevant code

- action: `/etc/fail2ban/action.d/sendmail-whois-lines-notes.conf`

```sh
Subject: [Fail2Ban] <name>: banned <ip> from <fq-hostname>
```

```sh
The IP <ip> has just been banned by Fail2Ban after
<failures> attempts against <name>.
```
