# Fail2Ban Monthly

Source: `/usr/local/bin/fail2ban-monthly-report.sh`

Schedule: monthly via `/etc/cron.d/fail2ban-monthly-report`

This mail is the monthly Fail2Ban SSH-oriented summary built from journal and `fail2ban.log`.

Recommended path shape:

- `YYYY-MM/email.txt`

Relevant code

- scheduler: `/etc/cron.d/fail2ban-monthly-report`
- script: `/usr/local/bin/fail2ban-monthly-report.sh`

```sh
0 8 1 * * root /usr/local/bin/fail2ban-monthly-report.sh
```

```sh
current_bans=$(fail2ban-client status sshd 2>/dev/null | sed -n 's/^\s*Banned IP list:\s*//p' || true)
} | mailx -s "Fail2Ban monthly report $month_label" "$report_email"
```
