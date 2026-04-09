X120x UPS Implementation

System view

- Geekworm X120x UPS HAT attached to the Pi 5
- AC power state read from GPIO pin 6 (PLD line)
- Battery level read from the MAX17043 fuel gauge over I2C at address 0x36
- two persistent daemons run as systemd services: one for event notification, one for shutdown
- monthly battery report sent via a separate systemd timer
- shutdown triggers at 20% battery when AC is confirmed lost

The UPS layer sits outside Docker and operates at the host level.
It is designed to act even when application containers are degraded or unresponsive.

What interacts with what

- `x120x-ups-notify` polls the GPIO PLD pin every 2 seconds and sends an email on AC loss or restore
- `x120x-ups-shutdown` polls battery capacity every 5 seconds and triggers a controlled shutdown when capacity reaches 20% with AC confirmed lost
- both services read configuration from `/etc/x120x/ups-notify.conf` and `/etc/x120x/ups-shutdown.conf`
- power events are written to a JSONL event log at `/var/log/x120x-ups-events.jsonl`
- email notifications are sent via msmtp to `xindy.notifications@gmail.com`
- the shutdown daemon reads the event log to determine AC state before falling back to direct GPIO

Why this design

- splitting notification and shutdown into separate daemons keeps the responsibilities clearer
- if the notification daemon fails, the shutdown path is not affected
- requiring AC loss confirmation before shutting down prevents false triggers from momentary battery fluctuation
- stopping Docker and key services before poweroff gives containers a clean exit window rather than a hard cut
- keeping the shutdown logic on the host rather than inside Docker means it can act even when containers are stuck

Flow

Notification flow

- notify daemon starts and reads current AC state from GPIO
- on AC loss, sends an email with host status, battery level, load, temperature, and memory
- on AC restore (if NOTIFY_ON_RESTORE is enabled), sends a restore notification
- all events are appended to the JSONL event log

Shutdown flow

- shutdown daemon confirms AC is lost
- polls battery level every 5 seconds
- when capacity reaches or falls below 20%, triggers the shutdown sequence:
  1. sends low-battery alert email
  2. runs quick backup (`/usr/local/sbin/ups-quick-backup.sh`) with a 5-minute timeout
  3. stops: docker, containerd, vncserver, lightdm, cups, zerotier-one, rp2350-stats
  4. syncs disks
  5. issues `systemctl poweroff`
- a state file at `/run/x120x-ups-shutdown.triggered` prevents the sequence from running twice

Reporting flow

- monthly systemd timer fires `x120x-ups-report.py`
- script reads the JSONL event log and summarises power events over the past month
- summary is emailed as a status report

Trade-offs

- GPIO-based AC detection is simple but provides no runtime validation of the UPS hardware itself
- a 20% threshold gives some time for the shutdown sequence to complete, but the actual remaining runtime depends on battery health and current load
- stopping services with a 25-second timeout per service is a reasonable balance, but slow-exiting containers can still exceed it
- the quick backup during shutdown adds safety but also adds time to the sequence — if the backup runs long, less time remains for clean service stops
- there is no watchdog on the UPS daemons beyond systemd's `Restart=on-failure` policy

What is here

- [service_model.md](service_model.md): daemon model, GPIO/I2C boundary, shutdown sequence, failure implications
- [issues_and_improvements.md](../../05_issues/x120x_ups.md): known gaps and next steps
- `config/`: sanitized copies of the notify and shutdown configuration files
