# Grafana Monthly

Source: `/srv/monitoring/bin/monthly-report.sh`

Schedule: monthly report generation is already present on the live system and writes into `/srv/monitoring/reports/YYYY-MM/`.

This folder is for the monthly Grafana-style report copy when that generated output is also mailed or mirrored into the repo workflow.

Recommended path shape:

- `YYYY-MM/email.txt`
- `YYYY-MM/report.txt`
- `YYYY-MM/metrics.csv`
- `YYYY-MM/*.png`

Relevant code

- script: `/srv/monitoring/bin/monthly-report.sh`
- output source: `/srv/monitoring/reports/YYYY-MM/`

```sh
MONTH="${1:-$(date -d 'last month' +%Y-%m)}"
OUT_DIR="/srv/monitoring/reports/$MONTH"
```

```sh
render_panel 1 "$OUT_DIR/temperature.png"
render_panel 11 "$OUT_DIR/smart.png"
```
