Issues And Improvements

Real issues already visible

NVMe boot drive has no scheduled SMART tests
The boot drive at `/dev/nvme0n1` is not covered by any systemd timer.
It currently has 38 unsafe shutdowns recorded, which is worth monitoring over time.
A problem on the NVMe would only be caught by a manual query or if pi-monitor is extended to cover it.

Short test result is never read back
The short test service initiates the test and exits.
Whether the test passed or failed is stored in the drive's internal SMART log but nothing reads it back, logs it, or alerts on the result.
The only signal from a failed short test comes through pi-monitor's attribute checks, not through the test result itself.

SMART coverage is limited to one of two drives in pi-monitor
Pi-monitor checks SMART attributes only on `/dev/sda`.
The NVMe is not part of the check cycle.

Test log coverage is asymmetric
Long test results are written to `/srv/monitoring/logs/smart-long.log`.
Short test results are not logged anywhere — the test initiates silently.

What I would change next

1. Add a scheduled SMART test for `/dev/nvme0n1` — at minimum a weekly short test to track the drive's health over time.
2. Extend pi-monitor to include NVMe attribute checks alongside the existing SATA checks.
3. Add a short test result read-back step — after initiating the test, wait for completion and log the result, or use a separate timer to read the result the following morning.
4. Standardise logging — short and long test outputs should both go to the same log path for consistent reporting.
