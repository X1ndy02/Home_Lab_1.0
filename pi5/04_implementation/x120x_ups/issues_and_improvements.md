Issues And Improvements

Real issues already visible

Quick backup failed during shutdown test (exit 126)
Tested 2026-03-03. The shutdown sequence ran but `ups-quick-backup.sh` exited with code 126 (permission or path error).
The shutdown still completed because the sequence does not halt on backup failure.
The backup failure was not investigated to root cause — it remains an open item.
See tracker issue #5.

No validation of UPS hardware at runtime
The daemons assume the HAT is present and functioning.
If the GPIO line or I2C bus drifts, returns stale data, or becomes unreadable, the daemons degrade silently.
There is no periodic health check that validates the fuel gauge is responding correctly.

Battery runtime at 20% is unknown
The 20% threshold was chosen without a measured discharge test.
Actual remaining runtime at 20% depends on battery age, current draw, and load at the moment of the event.
On a loaded Pi 5 with Docker stacks running, time available after threshold may be shorter than expected.

No monitoring of daemon health
Neither daemon is watched by the pi-monitor checks.
If a daemon fails and systemd exhausts its restart attempts, the UPS protection layer becomes inactive without any external alert.

Service stop timeout may not be enough
The 25-second per-service stop timeout was set without testing against Docker under heavy load.
During the UPS shutdown test, `nextcloud-clamav-1` required forced termination rather than a clean exit within the normal window.

What I would change next

1. Investigate and fix the exit 126 backup failure from the 2026-03-03 test — identify whether it is a path, permission, or script issue.
2. Add a pi-monitor check for UPS daemon status so a failed or inactive daemon produces an alert.
3. Run a discharge test to measure actual runtime at 20% battery under real load, then review whether the threshold needs adjusting.
4. Add a periodic I2C health check so fuel gauge communication failures become visible before a real power event depends on them.
5. Review the Docker stop timeout — consider increasing it or adding a `docker stop --time` call before stopping the docker.service unit itself.
