# Pi Monitor Monthly

Source: `/usr/local/sbin/weekly-pi-monitor-summary.py --monthly`

Schedule: monthly via `/etc/cron.d/monthly-pi-monitor-summary`

This mail is the monthly plain-text Pi monitor summary using the same reporting path as the weekly summary, but for the previous calendar month.

Recommended path shape:

- `YYYY-MM/email.txt`
- `YYYY-MM/pi-monitor-*.txt`
- `YYYY-MM/ssh-logins-*.txt`

Relevant code

- scheduler: `/etc/cron.d/monthly-pi-monitor-summary`
- script: `/usr/local/sbin/weekly-pi-monitor-summary.py`

```sh
0 8 1 * * root /usr/local/sbin/weekly-pi-monitor-summary.py --monthly
```

```python
subject = f"Monthly Pi Monitor Summary ({start.strftime('%Y-%m')})"
return send_mail(to_addr, from_addr, subject, body, attachments)
```
