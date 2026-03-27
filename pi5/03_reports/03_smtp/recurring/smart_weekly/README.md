# SMART Weekly

Source: `/usr/local/sbin/weekly-smartd-summary.py`

Schedule: weekly via `/etc/cron.d/weekly-smartd-summary`

This mail is the weekly SMART summary with a plain-text attachment containing the full smartd log lines for the period.

Recommended path shape:

- `YYYY-MM-DD/email.txt`
- `YYYY-MM-DD/smartd-log-YYYY-MM-DD.txt`

Relevant code

- scheduler: `/etc/cron.d/weekly-smartd-summary`
- script: `/usr/local/sbin/weekly-smartd-summary.py`

```sh
0 20 * * 0 root /usr/local/sbin/weekly-smartd-summary.py
```

```python
subject = f"Weekly SMART Summary ({now.strftime('%Y-%m-%d')})"
attach_name = f"smartd-log-{now.strftime('%Y-%m-%d')}.txt"
return send_mail(to_addr, from_addr, subject, body, attach_name, attachment)
```
