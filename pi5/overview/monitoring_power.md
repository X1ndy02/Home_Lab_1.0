Monitoring and Alerts

Monitoring is executed via a systemd timer that runs every minute.

Internal checks run at mixed intervals:
- Core system checks: every 5 minutes
- SSL certificate check: daily
- SSH failure detection: near-real-time via log parsing
- Weekly and monthly summary reports: via cron

Alert model
Most alerts are state-change based.
An alert is sent only when a condition changes from OK → WARN/CRIT or vice versa.

Exceptions:
- SSH failures trigger immediately.
- New SSH IP attempts and new successful SSH logins trigger immediately.

All alerts are sent individually via email.
There is no batching.

CPU temperature thresholds
- Warning: 65°C
- Critical: 70°C
- Static thresholds

System load
- Based on 1-minute load average
- Warning if load >= 4.0 for 3 consecutive minutes
- Fixed threshold (not normalized to CPU core count)

Disk usage
- Warning at 80%
- Critical at 90%

Docker container monitoring
- Checks for exited containers
- Does not inspect restart counts
- Does not inspect exit codes

SSL certificate monitoring
- Checked daily
- Warning at 30 days remaining
- Critical at 15 days remaining

SSH monitoring
- Log source: system journal (sshd)
- Alert threshold: 2 failed login attempts within a 15-minute window
- Immediate alert on:
  - New IP attempting SSH
  - New IP successful login

SMART disk monitoring
- Uses smartctl health and attribute checks
- Alerts on:
  - Overall health failure
  - Reallocated sectors > 0
  - Pending sectors > 0
  - Offline uncorrectable > 0
  - CRC errors > 10
  - Temperature > 55°C

SMART alerts use state-change gating to avoid repeated notifications.

Power Management
The UPS is monitored by two separate services.
AC state monitoring
- Poll interval: every 2 seconds

Battery level monitoring (during outage)
- Poll interval: every 5 seconds

Power loss behavior
When AC power is lost:
1. Immediate notification email is sent.
2. Event is logged.
3. System continues running on battery.

Low battery shutdown sequence (<= 20%)
When battery level reaches 20%:

1. Shutdown notification email is sent.
2. Quick backup script executes (rsync-based).
3. Docker services are stopped gracefully.
4. System performs controlled shutdown (poweroff).

There is no delay beyond the 5-second polling interval.
Service shutdown behavior
- Docker and container runtime are stopped via systemctl.
- Database container stops as part of Docker shutdown.
- No explicit database-specific shutdown command is issued.

Power restoration
- Restoration event triggers notification.
- AC-loss events and durations are included in monthly report.

Battery reporting
- Monthly report includes outage statistics.
- No long-term battery capacity trend analysis is performed.


Design intent
The monitoring and power system is designed for:
- Early detection of abnormal system behavior
- Immediate notification of security-relevant events
- Controlled shutdown to prevent filesystem corruption
- Data integrity during power loss
