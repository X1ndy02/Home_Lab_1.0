# Pi Monitor Weekly

Source: `/usr/local/sbin/weekly-pi-monitor-summary.py`

Schedule: weekly via `/etc/cron.d/weekly-pi-monitor-summary`

This mail is the weekly plain-text Pi monitor summary with text attachments generated from alert and SSH activity.

Recommended path shape:

- `YYYY-MM-DD/email.txt`
- `YYYY-MM-DD/pi-monitor-*.txt`
- `YYYY-MM-DD/ssh-logins-*.txt`

Relevant code

- scheduler: `/etc/cron.d/weekly-pi-monitor-summary`
- script: `/usr/local/sbin/weekly-pi-monitor-summary.py`

```sh
0 20 * * 0 root /usr/local/sbin/weekly-pi-monitor-summary.py
```

```python
subject = f"Weekly Pi Monitor Summary ({end.strftime('%Y-%m-%d')})"
return send_mail(to_addr, from_addr, subject, body, attachments)
```
