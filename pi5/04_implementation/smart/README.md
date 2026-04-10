SMART Implementation

System view

- SMART disk health monitoring via `smartctl` (smartmontools)
- two drives monitored: SATA SSD (`/dev/sda`, backup) and NVMe SSD (`/dev/nvme0n1`, boot)
- scheduled tests run on the SATA SSD only via systemd timers
- short test runs daily at 02:00 AEST
- long test runs weekly on Sunday at 03:00 AEST
- pi-monitor checks SMART health on both drives at every cycle as two separate named checks
- a weekly summary is generated and emailed as part of the weekly reporting flow

The NVMe boot drive is not included in scheduled tests — monitored only via pi-monitor each cycle.

What interacts with what

- systemd timers trigger `smartctl -t` to initiate tests on `/dev/sda`
- pi-monitor reads SMART data from `/dev/sda` and `/dev/nvme0n1` on each cycle and alerts on failures
- SATA and NVMe are tracked as separate checks (`SMART` and `SMART_NVME`) with independent state
- `weekly-smartd-summary.py` generates a summary email and archives it to the GitHub repo
- SMART data appears as a panel in the weekly Grafana report

Why this design

- SMART tests on the backup drive matter because it holds the only local copy of all snapshots
- daily short tests give a frequent signal without the longer runtime of a full extended test
- weekly long tests give deeper coverage without running every day
- NVMe monitoring uses different attributes to SATA (spare capacity, percentage used, media errors)
- keeping tests on the host rather than inside Docker means they still run even if containers are down
- separate check names mean SATA and NVMe alerts are independent — one failing does not suppress the other

Flow

Test flow

- short test timer fires at 02:00 AEST daily
- `smartctl -t short /dev/sda` initiates the test on the drive
- the drive runs the test internally; result is stored in the drive's SMART log
- long test timer fires at 03:00 AEST on Sundays, logs output to `/srv/monitoring/logs/smart-long.log`

SATA monitoring flow

- pi-monitor reads SMART health and attribute data from `/dev/sda` on each check cycle
- checks: overall health pass/fail, reallocated sectors, pending sectors, offline uncorrectable count, CRC errors, temperature
- any failure or threshold breach triggers an alert email and ntfy notification

NVMe monitoring flow

- pi-monitor reads SMART health and attribute data from `/dev/nvme0n1` on each check cycle
- checks: overall health pass/fail, available spare vs threshold, percentage used, media/data integrity errors, temperature
- CRIT if health fails or media errors > 0
- WARN if spare at or below threshold, percentage used >= 90%, or temperature > 60C

Reporting flow

- weekly summary script reads smartd logs and SMART attributes
- summary is emailed and archived to the GitHub repo via `smtp_archive.py`
- SMART panel appears in the weekly Grafana report

Trade-offs

- only the SATA SSD is covered by scheduled tests — the NVMe has no scheduled test timer
- the short test service only initiates the test and exits — it does not read back or log the result
- SMART provides early warning signals but cannot predict sudden mechanical or flash failures
- a single local backup drive means SMART failure and data loss are correlated risks

What is here

- [service_model.md](service_model.md): test schedule, monitoring integration, drive status, failure model
- [issues_and_improvements.md](../../05_issues/smart.md): known gaps and next steps
