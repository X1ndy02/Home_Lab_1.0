Service Model

Host and service boundary

Both UPS daemons run on the host, not inside Docker.

That matters because the shutdown sequence must be able to stop Docker itself.
A daemon running inside a container cannot reliably stop the runtime it depends on.
Placing shutdown logic on the host keeps it above the application layer.

Hardware interface model

AC state
- read from GPIO pin 6 (PLD line) on `/dev/gpiochip0`
- HIGH = AC present, LOW = AC lost
- polled every 2 seconds by the notify daemon, every 5 seconds by the shutdown daemon

Battery level
- read from the MAX17043 fuel gauge over I2C bus 1 at address `0x36`
- two registers: voltage (register 2) and state-of-charge in percent (register 4)
- read on each relevant poll cycle and on every email notification

Daemon model

`x120x-ups-notify` (Type=simple, Restart=on-failure)
- long-running process, stays alive for the lifetime of the system
- single responsibility: detect AC state changes and emit notifications
- writes all events to the JSONL event log

`x120x-ups-shutdown` (Type=simple, Restart=on-failure)
- long-running process, independent of notify
- reads AC state from the event log first, falls back to direct GPIO if the log is unavailable
- uses a state file at `/run/x120x-ups-shutdown.triggered` to ensure the shutdown sequence runs at most once per power event

`x120x-ups-report` (Type=oneshot, monthly timer)
- short-lived: runs once per month and exits
- reads the JSONL event log and sends a monthly summary email

Shutdown sequence

When battery capacity reaches or falls below 20% with AC confirmed lost:

1. Write trigger state file
2. Send low-battery alert email
3. Run quick backup — timeout 300 seconds
4. Stop services in sequence with a 25-second timeout each:
   - docker.service
   - containerd.service
   - vncserver-x11-serviced.service
   - lightdm.service
   - cups.service / cups-browsed.service
   - rp2350-stats.service
   - zerotier-one.service
5. Sync disks
6. Issue `systemctl poweroff`

The REQUIRE_AC_LOSS setting (enabled) means the shutdown daemon will not trigger on battery level alone — AC must be confirmed lost first.

Notification model

Every AC loss and restore event sends an email containing:
- host name, timestamp, AC state
- battery percentage and health label
- system uptime, load average, CPU temperature, memory, disk usage
- hardware model, OS, kernel version

Monthly report reads the event log and summarises AC loss/restore pairs, durations, and battery levels recorded during each event.

Failure model

- if the notify daemon crashes, AC loss events may not produce an email — systemd will restart it but brief outages during the crash window may be missed
- if the shutdown daemon crashes during a power event and restarts, the state file at `/run/x120x-ups-shutdown.triggered` prevents a double shutdown
- if the I2C read fails, battery level is unavailable — the shutdown daemon cannot trigger on capacity alone and will not act until the read recovers
- if the backup command during shutdown exits non-zero or times out, the sequence continues rather than halting — tested 2026-03-03, backup failed with exit 126, shutdown still completed
- if msmtp fails, notifications are silently lost
- if the state file path is unavailable, the shutdown sequence could run more than once
