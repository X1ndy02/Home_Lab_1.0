# Grafana Reports

Sources:

- `/srv/monitoring/bin/weekly-report.sh`
- `/srv/monitoring/bin/monthly-report.sh`

Schedule:

- weekly via `/etc/cron.d/weekly-pi-monitor-summary`
- monthly generation from the live monitoring stack

This folder is for report mails that include rendered Grafana graphs and report text.

Subject patterns:

- `[Pi Weekly Report] YYYY-MM-DD`
- `[Pi Monthly Report] YYYY-MM`

Recommended path shape:

- `weekly-YYYY-MM-DD/email.txt`
- `weekly-YYYY-MM-DD/report.txt`
- `weekly-YYYY-MM-DD/*.png`
- `YYYY-MM/email.txt`
- `YYYY-MM/report.txt`
- `YYYY-MM/*.png`

Relevant code

- scripts: `/srv/monitoring/bin/weekly-report.sh`, `/srv/monitoring/bin/monthly-report.sh`

```sh
0 20 * * 0 root /srv/monitoring/bin/weekly-report.sh
```

```sh
/srv/monitoring/bin/send-report.py \
  --subject "[Pi Weekly Report] $week_end" \
  --body-file "$OUT_DIR/report.txt" \
  --attach "$OUT_DIR/temperature.png"
```
