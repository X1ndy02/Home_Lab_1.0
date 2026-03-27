# Grafana Weekly

Source: `/srv/monitoring/bin/weekly-report.sh`

Schedule: weekly via `/etc/cron.d/weekly-pi-monitor-summary`

This mail sends the weekly Grafana report with rendered PNG attachments. The live system already stores matching artifacts under `/srv/monitoring/reports/weekly-YYYY-MM-DD/`.

Recommended path shape:

- `weekly-YYYY-MM-DD/email.txt`
- `weekly-YYYY-MM-DD/report.txt`
- `weekly-YYYY-MM-DD/*.png`

Relevant code

- scheduler: `/etc/cron.d/weekly-pi-monitor-summary`
- script: `/srv/monitoring/bin/weekly-report.sh`

```sh
0 20 * * 0 root /srv/monitoring/bin/weekly-report.sh
```

```sh
/srv/monitoring/bin/send-report.py \
  --subject "[Pi Weekly Report] $week_end" \
  --body-file "$OUT_DIR/report.txt" \
  --attach "$OUT_DIR/temperature.png"
```
