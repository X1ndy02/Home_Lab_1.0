# UPS Shutdown Alerts

Source: `/usr/local/bin/x120x-ups-shutdown.py`

Cadence: event-driven

This folder is for low-battery shutdown mails that announce the shutdown threshold crossing and the follow-up actions.

Recommended path shape:

- `YYYY-MM/YYYY-MM-DDTHH-MM-SS_low_battery_shutdown.txt`

Relevant code

- script: `/usr/local/bin/x120x-ups-shutdown.py`

```python
subject = f"{settings['subject_prefix']} LOW BATTERY {battery['capacity']:.1f}% - shutting down"
send_mail(settings, subject, body)
run_backup(settings)
stop_services(settings)
shutdown_system(settings)
```
