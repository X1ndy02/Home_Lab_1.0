Trackign sheet

| Scenario                 | Status      |  Issue  | Tets Name            |                 Notes                      |  Date tested   |
|--------------------------|-------------|---------|----------------------|--------------------------------------------|----------------|
| UPS Shutdown at 20%      | Partial     | #5      | ups_naturalshudown   | Backup failed (exit 126)                   |  03/03/2026    |
| Docker Full Stop         | Pending     | #4      | -                    | Not tested                                 |                |
| Disk Full                | Pending     | #3      | -                    | Not tested                                 |                |
| MariaDB Crash            | Pending     | #2      | -                    | Not tested                                 |                |
| Docker Healthchecks      | Pending     | #1      | -                    | Not implemented                            |                |

Status legend:
- Pending = Not tested
- Partial = Works but issue found
- Fail = Broken
- Pass = Fully validated
