#!/usr/bin/env bash
set -euo pipefail

report_email="alerts@example.invalid"

start_date=$(date -d "$(date +%Y-%m-01) -1 month" +%Y-%m-01)
end_date=$(date -d "$(date +%Y-%m-01)" +%Y-%m-01)
month_label=$(date -d "$start_date" +%Y-%m)
hostname=$(hostname)

ssh_journal=$(journalctl --since "$start_date" --until "$end_date" -u ssh -u sshd -o cat 2>/dev/null || true)
failed_lines=$(printf "%s\n" "$ssh_journal" | grep -E "Failed password|Invalid user|authentication failure" || true)
failed_ips=$(printf "%s\n" "$failed_lines" | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}" | sort | uniq -c | sort -nr || true)

f2b_log="/var/log/fail2ban.log"
ban_lines=$(grep -E "\[sshd\].* Ban " "$f2b_log" 2>/dev/null | awk -v start="$start_date" -v end="$end_date" '{ if ($1" "$2 >= start && $1" "$2 < end) print }' || true)
ban_ips=$(printf "%s\n" "$ban_lines" | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}" | sort | uniq -c | sort -nr || true)

current_bans=$(fail2ban-client status sshd 2>/dev/null | sed -n 's/^\s*Banned IP list:\s*//p' || true)

{
  echo "Fail2Ban monthly report for $hostname"
  echo "Period: $start_date to $end_date"
  echo
  echo "Current sshd bans:"
  if [ -n "$current_bans" ]; then
    echo "$current_bans"
  else
    echo "(none)"
  fi
  echo
  echo "Top SSH failed-login IPs in period:"
  if [ -n "$failed_ips" ]; then
    echo "$failed_ips"
  else
    echo "(none found)"
  fi
  echo
  echo "SSHD bans during period (from fail2ban.log):"
  if [ -n "$ban_ips" ]; then
    echo "$ban_ips"
  else
    echo "(none found)"
  fi
} | mailx -s "Fail2Ban monthly report $month_label" "$report_email"
