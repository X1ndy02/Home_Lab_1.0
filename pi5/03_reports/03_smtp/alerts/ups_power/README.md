# UPS Power Alerts

Source: `/usr/local/bin/x120x-ups-notify.py`

Cadence: event-driven

This folder is for immediate UPS power mails such as `AC LOST` and `AC RESTORED`.

Recommended path shape:

- `YYYY-MM/YYYY-MM-DDTHH-MM-SS_ac_lost.txt`
- `YYYY-MM/YYYY-MM-DDTHH-MM-SS_ac_restored.txt`

Relevant code

- service: `/etc/systemd/system/x120x-ups-notify.service`
- script: `/usr/local/bin/x120x-ups-notify.py`

```python
subject = f"{settings['subject_prefix']} POWER EVENT · AC LOST"
...
subject = f"{settings['subject_prefix']} POWER EVENT · AC RESTORED"
```
