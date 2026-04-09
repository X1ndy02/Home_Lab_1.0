Service Model

Host and service boundary

SMART monitoring runs entirely on the host.
`smartctl` communicates directly with drive hardware — it cannot run usefully inside a container without elevated privileges and device passthrough.
Keeping it on the host is the only practical choice.

Drive inventory

| Device | Model | Capacity | Role | Health |
|--------|-------|----------|------|--------|
| `/dev/sda` | Kingston SA400S37240G | 240 GB SATA SSD | Backup target | PASSED |
| `/dev/nvme0n1` | Kingston SNV2S500G | 500 GB NVMe SSD | Boot drive | PASSED |

SATA SSD attributes (last read):
- Power-on hours: 1,872
- Reallocated sectors: 0
- Reported uncorrectable: 0
- Temperature: 34°C (max seen: 45°C)

NVMe attributes (last read):
- Percentage used: 0%
- Unsafe shutdowns: 38
- Temperature: 40°C

Test schedule model

| Test | Device | Schedule | Timer |
|------|--------|----------|-------|
| Short | `/dev/sda` | Daily 02:00 AEST | `smart-short-test.timer` |
| Long | `/dev/sda` | Sunday 03:00 AEST | `smart-long-test.timer` |

The short test service runs `smartctl -t short /dev/sda` and exits.
This only initiates the test — the drive performs it internally.
Results are stored in the drive's SMART log and readable via `smartctl -l selftest /dev/sda`.
The short test service does not read back or record the result itself.

The long test logs its output to `/srv/monitoring/logs/smart-long.log`.

The NVMe drive has no scheduled tests configured.

Monitoring integration model

Pi-monitor reads the following from `/dev/sda` on each check cycle:
- overall SMART health assessment (`PASSED` / `FAILED`)
- reallocated sector count
- pending sector count
- offline uncorrectable count
- UDMA CRC error count
- temperature

Any breach of thresholds or a health failure triggers an email alert via the same notification path used by all pi-monitor checks.

Reporting model

`weekly-smartd-summary.py` runs as part of the weekly reporting cycle.
It reads smartd log data and SMART attributes, generates a summary, and emails it.
The summary is archived to the GitHub repo via `smtp_archive.py`.
A SMART panel also appears in the weekly Grafana report image.

Failure model

- if the SATA SSD fails a SMART self-assessment, pi-monitor will alert on the next check cycle
- if a drive develops reallocated or pending sectors, pi-monitor detects them at the attribute level before a health failure is declared
- if the test timers are disabled, no scheduled tests run — the drive's internal SMART log goes stale, but pi-monitor attribute checks still run independently
- if pi-monitor itself fails, SMART alerting stops silently
- if the NVMe develops a problem, it will not be caught by scheduled tests — only a manual `smartctl -a /dev/nvme0n1` would show it
