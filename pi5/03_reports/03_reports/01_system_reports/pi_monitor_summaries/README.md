# Pi Monitor Summaries

Source: `/usr/local/sbin/weekly-pi-monitor-summary.py`

Schedule:

- weekly via `/etc/cron.d/weekly-pi-monitor-summary`
- monthly via `/etc/cron.d/monthly-pi-monitor-summary`

This folder is for the summary emails generated from Pi monitor alert history and SSH activity.

Subject patterns:

- `Weekly Pi Monitor Summary (...)`
- `Monthly Pi Monitor Summary (...)`

Recommended path shape:

- `weekly-YYYY-MM-DD/email.txt`
- `weekly-YYYY-MM-DD/pi-monitor-*.txt`
- `weekly-YYYY-MM-DD/ssh-logins-*.txt`
- `YYYY-MM/email.txt`

Relevant code

- schedulers: `/etc/cron.d/weekly-pi-monitor-summary`, `/etc/cron.d/monthly-pi-monitor-summary`
- script: `/usr/local/sbin/weekly-pi-monitor-summary.py`

```sh
0 20 * * 0 root /usr/local/sbin/weekly-pi-monitor-summary.py
0 8 1 * * root /usr/local/sbin/weekly-pi-monitor-summary.py --monthly
```

```python
subject = f"Weekly Pi Monitor Summary ({end.strftime('%Y-%m-%d')})"
subject = f"Monthly Pi Monitor Summary ({start.strftime('%Y-%m')})"
```
