# Partition Health Alerts

Source: `/usr/local/sbin/partition-health-check.py`

Cadence: daily check, alert only on issue

This folder is for filesystem dirty-bit or unclean-state alert mails sent by the partition health check.

Recommended path shape:

- `YYYY-MM/YYYY-MM-DDTHH-MM-SS_dirty_fs_alert.txt`

Relevant code

- scheduler: `/etc/cron.d/partition-health-check`
- script: `/usr/local/sbin/partition-health-check.py`

```sh
0 20 * * * root /usr/local/sbin/partition-health-check.py
```

```python
subject = f"ALERT: Dirty/unclean filesystem detected ({ts})"
send_smtp(cfg, subject, body)
```
