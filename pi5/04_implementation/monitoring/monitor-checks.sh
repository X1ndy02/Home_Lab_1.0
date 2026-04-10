#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/srv/monitoring/state"
LOG_DIR="/srv/monitoring/logs"
METRICS_DIR="/srv/monitoring/metrics"
MSMTP_CONF="/srv/monitoring/msmtp.conf"
TO_EMAIL="xindy.notifications@gmail.com"
NTFY_URL="http://10.244.10.4:8080"
NTFY_TOPIC="rootnode-7996ee61"
ARCHIVE_REPO="/home/xindy/Desktop/Home_Lab_1.0"
ARCHIVE_SCRIPT="$ARCHIVE_REPO/scripts/smtp_archive.py"
ARCHIVE_TOKEN_FILE="/home/xindy/Desktop/github_token.txt"

NC_URL="https://10.244.10.244"
NC_STATUS_URL="$NC_URL/status.php"
SSL_HOST="10.244.10.244"
PING_TARGETS=("1.1.1.1" "8.8.8.8")
SSH_SERVICE="ssh"
SMART_DEV="/dev/sda"
SMART_NVME="/dev/nvme0n1"

CPU_WARN=65
CPU_CRIT=70
LOAD_WARN_TENTHS=40
LOAD_WARN_MINUTES=3
RAM_WARN=90
RAM_WARN_MINUTES=5
SWAP_WARN=75
SWAP_WARN_MINUTES=3
DISK_WARN=80
DISK_CRIT=90
PING_INTERVAL=300
PING_FAILS=2
HTTP_FAILS=3
LOGIN_INTERVAL=300
LOGIN_WINDOW_MIN=15
LOGIN_THRESHOLD=2
SSL_CHECK_INTERVAL=86400
SSL_WARN_DAYS=30
SSL_CRIT_DAYS=15
METRIC_INTERVAL=300

SERVICES=("ssh" "docker" "nginx")

mkdir -p "$STATE_DIR" "$LOG_DIR" "$METRICS_DIR" "$STATE_DIR/net"

from_email=$(awk '$1=="from" {print $2}' "$MSMTP_CONF" 2>/dev/null || true)

archive_pi_monitor_email() {
  local subject="$1"
  local body="$2"
  local tmp_dir tmp_body archive_output archive_status
  local -a cmd

  tmp_dir=$(mktemp -d)
  tmp_body="$tmp_dir/email-body.txt"
  printf '%s\n' "$body" > "$tmp_body"
  chmod 755 "$tmp_dir"
  chmod 644 "$tmp_body"

  cmd=(
    sudo -u xindy
    env
    "SMTP_ARCHIVE_GITHUB_TOKEN_FILE=$ARCHIVE_TOKEN_FILE"
    python3
    "$ARCHIVE_SCRIPT"
    --repo
    "$ARCHIVE_REPO"
    --source
    pi_monitor_alert
    --timestamp
    "$(date -Is)"
    --from-addr
    "$from_email"
    --to-addr
    "$TO_EMAIL"
    --subject
    "$subject"
    --body-file
    "$tmp_body"
    --push
  )

  set +e
  archive_output="$("${cmd[@]}" 2>&1)"
  archive_status=$?
  set -e

  rm -rf "$tmp_dir"
  if [ "$archive_status" -ne 0 ]; then
    printf '%s' "$archive_output"
    return "$archive_status"
  fi
  return 0
}

send_email() {
  local subject="$1"
  local body="$2"
  local skip_archive="${3:-0}"
  local archive_output
  if [ -z "$from_email" ] || [ ! -s "$MSMTP_CONF" ]; then
    echo "[$(date +%FT%T%z)] Email not configured; skipping send: $subject" >> "$LOG_DIR/alerts.log"
    return
  fi
  {
    echo "From: $from_email"
    echo "To: $TO_EMAIL"
    echo "Subject: $subject"
    echo
    echo "$body"
  } | msmtp -C "$MSMTP_CONF" -t

  if [ "$skip_archive" != "1" ] && [[ "$subject" == "[Pi Monitor]"* ]]; then
    if ! archive_output=$(archive_pi_monitor_email "$subject" "$body"); then
      echo "[$(date +%FT%T%z)] SMTP archive push failed: $archive_output" >> "$LOG_DIR/alerts.log"
      send_email \
        "Git push failed" \
        "A git push did not complete successfully for the Pi monitor alert archive.

Original subject: $subject
Repository: $ARCHIVE_REPO

Error:
$archive_output" \
        1
    fi
  fi
}

log_alert() {
  local name="$1"
  local status="$2"
  local msg="$3"
  echo "[$(date +%FT%T%z)] $name $status - $msg" >> "$LOG_DIR/alerts.log"
}

set_state() {
  echo "$2" > "$STATE_DIR/$1"
}

get_state() {
  if [ -f "$STATE_DIR/$1" ]; then
    cat "$STATE_DIR/$1"
  else
    echo "$2"
  fi
}

send_ntfy() {
  local title="$1"
  local msg="$2"
  local priority="${3:-default}"
  curl -s --max-time 5 \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -d "$msg" \
    "$NTFY_URL/$NTFY_TOPIC" >/dev/null 2>&1 || true
}

check_and_alert() {
  local name="$1"
  local status="$2"
  local msg="$3"
  local prev
  prev=$(get_state "$name.status" "UNKNOWN")
  if [ "$status" != "$prev" ]; then
    set_state "$name.status" "$status"
    log_alert "$name" "$status" "$msg"
    send_email "[Pi Monitor] $name $status" "$msg"
    local prio="default"
    [[ "$status" == "CRIT" ]] && prio="urgent"
    [[ "$status" == "WARN" ]] && prio="high"
    send_ntfy "[Pi Monitor] $name $status" "$msg" "$prio"
  fi
}

now=$(date +%s)

temp_c=0
load1=0
ram_used_pct=0
swap_used_pct=0
root_use=0
throttled_hex="0x0"
throttled_current=0
throttled_history=0
fs_err_recent=0
fs_err_total=$(get_state "fs.error_total" 0)
smart_health_ok=0
smart_realloc=0
smart_pending=0
smart_offline=0
smart_crc=0
smart_temp=0

# Nextcloud HTTPS check (1 min, alert after 3 fails)
http_fail=$(get_state "nextcloud_http.failcount" 0)
if curl -ksS --max-time 10 "$NC_STATUS_URL" > /dev/null; then
  http_fail=0
  check_and_alert "NEXTCLOUD" "OK" "HTTPS reachable: $NC_URL"
else
  http_fail=$((http_fail+1))
  if [ "$http_fail" -ge "$HTTP_FAILS" ]; then
    check_and_alert "NEXTCLOUD" "CRIT" "HTTPS check failing $http_fail times: $NC_URL"
  fi
fi
set_state "nextcloud_http.failcount" "$http_fail"

# SSH service check
if systemctl is-active --quiet "$SSH_SERVICE"; then
  check_and_alert "SSH" "OK" "SSH service is active"
else
  check_and_alert "SSH" "CRIT" "SSH service is not active"
fi

# Internet ping check (every 5 min, alert after 2 fails)
last_ping=$(get_state "ping.last" 0)
if [ $((now - last_ping)) -ge "$PING_INTERVAL" ]; then
  ping_fail=$(get_state "ping.failcount" 0)
  ping_ok=0
  for target in "${PING_TARGETS[@]}"; do
    if ping -c 1 -W 2 "$target" > /dev/null 2>&1; then
      ping_ok=1
      break
    fi
  done
  if [ "$ping_ok" -eq 1 ]; then
    ping_fail=0
    check_and_alert "PING" "OK" "Ping OK: ${PING_TARGETS[*]}"
  else
    ping_fail=$((ping_fail+1))
    if [ "$ping_fail" -ge "$PING_FAILS" ]; then
      check_and_alert "PING" "CRIT" "Ping failed $ping_fail times: ${PING_TARGETS[*]}"
    fi
  fi
  set_state "ping.failcount" "$ping_fail"
  set_state "ping.last" "$now"
fi

# CPU temperature
if command -v vcgencmd >/dev/null 2>&1; then
  temp_raw=$(vcgencmd measure_temp | cut -d= -f2 | tr -d "'C")
  temp_c=${temp_raw%.*}
  if [ "$temp_c" -ge "$CPU_CRIT" ]; then
    check_and_alert "CPU_TEMP" "CRIT" "CPU temp ${temp_c}C >= ${CPU_CRIT}C"
  elif [ "$temp_c" -ge "$CPU_WARN" ]; then
    check_and_alert "CPU_TEMP" "WARN" "CPU temp ${temp_c}C >= ${CPU_WARN}C"
  else
    check_and_alert "CPU_TEMP" "OK" "CPU temp ${temp_c}C"
  fi
fi

# Load average (1 min) for 3 minutes
load1=$(awk '{print $1}' /proc/loadavg)
load_tenths=$(awk -v v="$load1" 'BEGIN{printf "%d", v*10}')
load_high=$(get_state "load.highcount" 0)
if [ "$load_tenths" -ge "$LOAD_WARN_TENTHS" ]; then
  load_high=$((load_high+1))
else
  load_high=0
fi
set_state "load.highcount" "$load_high"
if [ "$load_high" -ge "$LOAD_WARN_MINUTES" ]; then
  check_and_alert "LOAD" "WARN" "Load ${load1} >= 4.0 for ${LOAD_WARN_MINUTES} min"
else
  check_and_alert "LOAD" "OK" "Load ${load1}"
fi

# RAM usage (90% for 5 min)
read -r _ mem_total mem_used mem_free mem_shared mem_buff mem_available < <(free -m | awk '/^Mem:/ {print $1,$2,$3,$4,$5,$6,$7}')
ram_used_pct=$(( (mem_total - mem_available) * 100 / mem_total ))
ram_high=$(get_state "ram.highcount" 0)
if [ "$ram_used_pct" -ge "$RAM_WARN" ]; then
  ram_high=$((ram_high+1))
else
  ram_high=0
fi
set_state "ram.highcount" "$ram_high"
if [ "$ram_high" -ge "$RAM_WARN_MINUTES" ]; then
  check_and_alert "RAM" "WARN" "RAM usage ${ram_used_pct}% >= ${RAM_WARN}% for ${RAM_WARN_MINUTES} min"
else
  check_and_alert "RAM" "OK" "RAM usage ${ram_used_pct}%"
fi

# Swap usage (75% for 3 min)
read -r _ swap_total swap_used swap_free < <(free -m | awk '/^Swap:/ {print $1,$2,$3,$4}')
if [ "$swap_total" -gt 0 ]; then
  swap_used_pct=$(( swap_used * 100 / swap_total ))
  swap_high=$(get_state "swap.highcount" 0)
  if [ "$swap_used_pct" -ge "$SWAP_WARN" ]; then
    swap_high=$((swap_high+1))
  else
    swap_high=0
  fi
  set_state "swap.highcount" "$swap_high"
  if [ "$swap_high" -ge "$SWAP_WARN_MINUTES" ]; then
    check_and_alert "SWAP" "WARN" "Swap usage ${swap_used_pct}% >= ${SWAP_WARN}% for ${SWAP_WARN_MINUTES} min"
  else
    check_and_alert "SWAP" "OK" "Swap usage ${swap_used_pct}%"
  fi
else
  check_and_alert "SWAP" "OK" "Swap disabled"
fi

# Disk usage
root_use=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
if [ "$root_use" -ge "$DISK_CRIT" ]; then
  check_and_alert "DISK" "CRIT" "Disk usage ${root_use}% >= ${DISK_CRIT}%"
elif [ "$root_use" -ge "$DISK_WARN" ]; then
  check_and_alert "DISK" "WARN" "Disk usage ${root_use}% >= ${DISK_WARN}%"
else
  check_and_alert "DISK" "OK" "Disk usage ${root_use}%"
fi

# Docker containers down
if command -v docker >/dev/null 2>&1; then
  exited=$(docker ps -a --filter "status=exited" --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')
  if [ -n "$exited" ]; then
    check_and_alert "DOCKER" "CRIT" "Exited containers: $exited"
  else
    check_and_alert "DOCKER" "OK" "All containers running"
  fi
else
  check_and_alert "DOCKER" "WARN" "Docker not available"
fi

# Undervoltage/throttling
if command -v vcgencmd >/dev/null 2>&1; then
  throttled_hex=$(vcgencmd get_throttled | cut -d= -f2)
  throttled_hex=${throttled_hex:-0x0}
  throttled_val=$((throttled_hex))
  throttled_current=0
  throttled_history=0
  if [ $((throttled_val & 0xF)) -ne 0 ]; then
    throttled_current=1
  fi
  if [ $((throttled_val & 0xF0000)) -ne 0 ]; then
    throttled_history=1
  fi
  if [ "$throttled_current" -eq 1 ]; then
    check_and_alert "POWER" "CRIT" "Current throttling detected: $throttled_hex"
  else
    check_and_alert "POWER" "OK" "No current throttling detected (flags: $throttled_hex)"
  fi
fi

# SMART health (advanced)
if command -v smartctl >/dev/null 2>&1 && [ -b "$SMART_DEV" ]; then
  smart_out=$(smartctl -H -A "$SMART_DEV" 2>/dev/null || true)
  if echo "$smart_out" | grep -q "PASSED"; then
    smart_health_ok=1
  else
    smart_health_ok=0
  fi
  smart_realloc=$(echo "$smart_out" | awk '$1=="5" {print $10}' | tail -n1)
  smart_pending=$(echo "$smart_out" | awk '$1=="197" {print $10}' | tail -n1)
  smart_offline=$(echo "$smart_out" | awk '$1=="198" {print $10}' | tail -n1)
  smart_crc=$(echo "$smart_out" | awk '$1=="199" {print $10}' | tail -n1)
  smart_temp=$(echo "$smart_out" | awk '$1=="194" {print $10}' | tail -n1)
  smart_realloc=${smart_realloc:-0}
  smart_pending=${smart_pending:-0}
  smart_offline=${smart_offline:-0}
  smart_crc=${smart_crc:-0}
  smart_temp=${smart_temp:-0}
  if [ "$smart_health_ok" -eq 0 ]; then
    msg=$(printf "SMART health FAIL on %s\n\nSMART attributes:\n  realloc=%s\n  pending=%s\n  offline=%s\n  crc=%s\n  temp=%sC\n\nSMART output:\n%s" "$SMART_DEV" "$smart_realloc" "$smart_pending" "$smart_offline" "$smart_crc" "$smart_temp" "$smart_out")
    check_and_alert "SMART" "CRIT" "$msg"
  elif [ "$smart_realloc" -gt 0 ] || [ "$smart_pending" -gt 0 ] || [ "$smart_offline" -gt 0 ] || [ "$smart_crc" -gt 10 ] || [ "$smart_temp" -gt 55 ]; then
    check_and_alert "SMART" "WARN" "SMART warn on $SMART_DEV: realloc=$smart_realloc pending=$smart_pending offline=$smart_offline crc=$smart_crc temp=${smart_temp}C"
  else
    check_and_alert "SMART" "OK" "SMART OK on $SMART_DEV (temp ${smart_temp}C)"
  fi
fi

# SMART health — NVMe (boot drive)
if command -v smartctl >/dev/null 2>&1 && [ -b "$SMART_NVME" ]; then
  nvme_out=$(smartctl -H -A "$SMART_NVME" 2>/dev/null || true)
  if echo "$nvme_out" | grep -q "PASSED"; then
    nvme_health_ok=1
  else
    nvme_health_ok=0
  fi
  nvme_spare=$(echo "$nvme_out" | awk '/Available Spare:/ {gsub(/%/,"",$NF); print $NF}' | head -1)
  nvme_spare_thresh=$(echo "$nvme_out" | awk '/Available Spare Threshold:/ {gsub(/%/,"",$NF); print $NF}' | head -1)
  nvme_used=$(echo "$nvme_out" | awk '/Percentage Used:/ {gsub(/%/,"",$NF); print $NF}' | head -1)
  nvme_errors=$(echo "$nvme_out" | awk '/Media and Data Integrity Errors:/ {print $NF}' | head -1)
  nvme_temp=$(echo "$nvme_out" | awk '/^Temperature:/ {print $2}' | head -1)
  nvme_spare=${nvme_spare:-100}
  nvme_spare_thresh=${nvme_spare_thresh:-10}
  nvme_used=${nvme_used:-0}
  nvme_errors=${nvme_errors:-0}
  nvme_temp=${nvme_temp:-0}
  if [ "$nvme_health_ok" -eq 0 ] || [ "$nvme_errors" -gt 0 ]; then
    msg=$(printf "SMART health FAIL on %s\n\nNVMe attributes:\n  available_spare=%s%%\n  percentage_used=%s%%\n  media_errors=%s\n  temp=%sC\n\nSMART output:\n%s" "$SMART_NVME" "$nvme_spare" "$nvme_used" "$nvme_errors" "$nvme_temp" "$nvme_out")
    check_and_alert "SMART_NVME" "CRIT" "$msg"
  elif [ "$nvme_spare" -le "$nvme_spare_thresh" ] || [ "$nvme_used" -ge 90 ] || [ "$nvme_temp" -gt 60 ]; then
    check_and_alert "SMART_NVME" "WARN" "SMART warn on $SMART_NVME: spare=${nvme_spare}% used=${nvme_used}% errors=$nvme_errors temp=${nvme_temp}C"
  else
    check_and_alert "SMART_NVME" "OK" "SMART OK on $SMART_NVME (spare=${nvme_spare}% used=${nvme_used}% temp=${nvme_temp}C)"
  fi
fi

# Failed SSH logins (alert on any new failure; include IP)
last_login=$(get_state "login.last" 0)
if [ "$last_login" -le 0 ]; then
  last_login=$((now - LOGIN_INTERVAL))
fi
ssh_lines=$(journalctl -u ssh -u sshd --since "@${last_login}" 2>/dev/null | grep -Ei "Failed|Accepted|authentication failure" || true)

# Correlate failures -> success for same IP + user within 15 minutes
window_sec=$((15 * 60))
min_failures=2
now_epoch=$(date +%s)
cache_file="$STATE_DIR/ssh-failures.cache"
known_attempt_file="$STATE_DIR/ssh-known-ips.cache"
known_login_file="$STATE_DIR/ssh-known-ips-success.cache"

is_allowed_ip() {
  case "$1" in
    10.244.10.*) return 0 ;;
    127.0.0.1|::1) return 0 ;;
  esac
  return 1
}

# Known IPs for attempts (any) and successful logins.
declare -A known_attempt
declare -A known_login
append_attempt=""
append_login=""

if [ -f "$known_attempt_file" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    ip="${line%%|*}"  # backward-compatible with older "ip|user" entries
    [ -z "$ip" ] && continue
    known_attempt[$ip]=1
  done < "$known_attempt_file"
fi

if [ -f "$known_login_file" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    ip="${line%%|*}"  # backward-compatible with older "ip|user" entries
    [ -z "$ip" ] && continue
    known_login[$ip]=1
  done < "$known_login_file"
fi


declare -A fail_counts
declare -A fail_first
declare -A fail_last

pruned_cache=""
if [ -f "$cache_file" ]; then
  while IFS='|' read -r epoch ip user; do
    [ -z "$epoch" ] && continue
    if [ $((now_epoch - epoch)) -le $window_sec ]; then
      pruned_cache+="$epoch|$ip|$user\n"
      key="$ip|$user"
      count=${fail_counts[$key]:-0}
      fail_counts[$key]=$((count + 1))
      first=${fail_first[$key]:-}
      if [ -z "$first" ] || [ "$epoch" -lt "$first" ]; then
        fail_first[$key]="$epoch"
      fi
      last=${fail_last[$key]:-}
      if [ -z "$last" ] || [ "$epoch" -gt "$last" ]; then
        fail_last[$key]="$epoch"
      fi
    fi
  done < "$cache_file"
fi

# Build failure alert details
ip_list=""
port_list=""
user_list=""
method_list=""
invalid_seen=0
valid_seen=0
fail_count=0
extra_count=0
earliest_epoch=""
latest_epoch=""
earliest_ts=""
latest_ts=""
timeline=""

while IFS= read -r line; do
  [ -z "$line" ] && continue
  ts=$(printf "%s\n" "$line" | awk '{print $1" "$2" "$3}')
  time_only=$(printf "%s\n" "$ts" | awk '{print $3}')
  epoch=$(date -d "$ts" +%s 2>/dev/null || echo "")
  if [ -n "$epoch" ]; then
    if [ -z "$earliest_epoch" ] || [ "$epoch" -lt "$earliest_epoch" ]; then
      earliest_epoch="$epoch"
      earliest_ts="$ts"
    fi
    if [ -z "$latest_epoch" ] || [ "$epoch" -gt "$latest_epoch" ]; then
      latest_epoch="$epoch"
      latest_ts="$ts"
    fi
  fi

  # Success correlation
  if [[ "$line" =~ Accepted[[:space:]]+([[:alnum:]_/-]+)[[:space:]]+for[[:space:]]+([^[:space:]]+)[[:space:]]+from[[:space:]]+([^[:space:]]+)[[:space:]]+port[[:space:]]+([0-9]+) ]]; then
    method_ok="${BASH_REMATCH[1]}"
    user_ok="${BASH_REMATCH[2]}"
    ip_ok="${BASH_REMATCH[3]}"
    port_ok="${BASH_REMATCH[4]}"
    key="$ip_ok|$user_ok"

    if is_allowed_ip "$ip_ok"; then
      if [ -z "${known_attempt[$ip_ok]:-}" ]; then
        known_attempt[$ip_ok]=1
        append_attempt+="$ip_ok\n"
      fi
      if [ -z "${known_login[$ip_ok]:-}" ]; then
        known_login[$ip_ok]=1
        append_login+="$ip_ok\n"
      fi
    else
      if [ -z "${known_attempt[$ip_ok]:-}" ]; then
        known_attempt[$ip_ok]=1
        append_attempt+="$ip_ok\n"
        msg_new_attempt=$(printf "SSH ALERT · NEW IP ATTEMPT
─────────────────────────
Host    : %s
User    : %s
Source  : %s
Time    : %s
Method  : %s
Port    : %s
Result  : ACCEPTED" "$(hostname)" "$user_ok" "$ip_ok" "$ts" "$method_ok" "$port_ok")
        send_email "[Pi Monitor] SSH NEW IP ATTEMPT" "$msg_new_attempt"
      fi

      if [ -z "${known_login[$ip_ok]:-}" ]; then
        known_login[$ip_ok]=1
        append_login+="$ip_ok\n"
        msg_new_login=$(printf "SSH ALERT · NEW IP LOGIN
───────────────────────
Host    : %s
User    : %s
Source  : %s
Time    : %s
Method  : %s
Port    : %s" "$(hostname)" "$user_ok" "$ip_ok" "$ts" "$method_ok" "$port_ok")
        send_email "[Pi Monitor] SSH NEW IP LOGIN" "$msg_new_login"
      fi
    fi

    count=${fail_counts[$key]:-0}
    if [ "$count" -ge $min_failures ]; then
      first_epoch=${fail_first[$key]:-}
      last_epoch=${fail_last[$key]:-}
      if [ -n "$first_epoch" ] && [ -n "$last_epoch" ]; then
        first_ts=$(date -d "@${first_epoch}" "+%b %d %H:%M:%S")
        last_ts=$(date -d "@${last_epoch}" "+%b %d %H:%M:%S")
        window_msg="$first_ts → $last_ts"
      else
        window_msg="(unknown)"
      fi

      msg=$(printf "SSH ALERT · FAILED THEN SUCCESS
──────────────────────────────
Host    : %s
User    : %s
Source  : %s
Failures: %s within last 15 min
Window  : %s
Success : %s (method=%s, port=%s)" "$(hostname)" "$user_ok" "$ip_ok" "$count" "$window_msg" "$ts" "$method_ok" "$port_ok")
      send_email "[Pi Monitor] SSH LOGIN RECOVERED" "$msg"
    fi
    continue
  fi

  # PAM summary
  if echo "$line" | grep -qi "more authentication failures"; then
    extra=$(printf "%s\n" "$line" | sed -n 's/.*\([0-9][0-9]*\) more authentication failures.*/\1/p')
    if [ -n "$extra" ]; then
      extra_count=$((extra_count + extra))
      timeline+=$(printf "• %s  %s more authentication failures (pam summary)\n" "$time_only" "$extra")
      continue
    fi
  fi

  # PAM single failure
  if echo "$line" | grep -qi "authentication failure"; then
    fail_count=$((fail_count + 1))
    timeline+=$(printf "• %s  password check failed (pam)\n" "$time_only")
    continue
  fi

  # Failed password
  if [[ "$line" =~ Failed[[:space:]]+([[:alnum:]_/-]+)[[:space:]]+for[[:space:]]+(invalid[[:space:]]+user[[:space:]]+)?([^[:space:]]+)[[:space:]]+from[[:space:]]+([^[:space:]]+)[[:space:]]+port[[:space:]]+([0-9]+) ]]; then
    method="${BASH_REMATCH[1]}"
    invalid_flag="${BASH_REMATCH[2]}"
    user="${BASH_REMATCH[3]}"
    ip="${BASH_REMATCH[4]}"
    port="${BASH_REMATCH[5]}"

    if is_allowed_ip "$ip"; then
      if [ -z "${known_attempt[$ip]:-}" ]; then
        known_attempt[$ip]=1
        append_attempt+="$ip\n"
      fi
    else
      if [ -z "${known_attempt[$ip]:-}" ]; then
        known_attempt[$ip]=1
        append_attempt+="$ip\n"
        msg_new_attempt=$(printf "SSH ALERT · NEW IP ATTEMPT
─────────────────────────
Host    : %s
User    : %s
Source  : %s
Time    : %s
Method  : %s
Port    : %s
Result  : FAILED" "$(hostname)" "$user" "$ip" "$ts" "$method" "$port")
        send_email "[Pi Monitor] SSH NEW IP ATTEMPT" "$msg_new_attempt"
      fi
    fi

    if [ -n "$invalid_flag" ]; then
      invalid_seen=1
    else
      valid_seen=1
    fi
    ip_list+="$ip\n"
    port_list+="$port\n"
    user_list+="$user\n"
    method_list+="$method\n"
    fail_count=$((fail_count + 1))
    timeline+=$(printf "• %s  failed password for %s from %s:%s\n" "$time_only" "$user" "$ip" "$port")

    # Update failure cache for correlation
    if [ -n "$epoch" ]; then
      key="$ip|$user"
      count=${fail_counts[$key]:-0}
      fail_counts[$key]=$((count + 1))
      first=${fail_first[$key]:-}
      if [ -z "$first" ] || [ "$epoch" -lt "$first" ]; then
        fail_first[$key]="$epoch"
      fi
      last=${fail_last[$key]:-}
      if [ -z "$last" ] || [ "$epoch" -gt "$last" ]; then
        fail_last[$key]="$epoch"
      fi
      pruned_cache+="$epoch|$ip|$user\n"
    fi
  fi

done <<< "$ssh_lines"

# Persist failure cache
if [ -n "$pruned_cache" ]; then
  printf "%b" "$pruned_cache" > "$cache_file"
else
  : > "$cache_file"
fi

# Persist known IPs
if [ -n "$append_attempt" ] || [ -f "$known_attempt_file" ]; then
  { [ -f "$known_attempt_file" ] && cat "$known_attempt_file"; printf "%b" "$append_attempt"; } \
    | awk "NF" \
    | awk -F'|' "{print \$1}" \
    | sort -u > "$known_attempt_file"
fi

if [ -n "$append_login" ] || [ -f "$known_login_file" ]; then
  { [ -f "$known_login_file" ] && cat "$known_login_file"; printf "%b" "$append_login"; } \
    | awk "NF" \
    | awk -F'|' "{print \$1}" \
    | sort -u > "$known_login_file"
fi

fail_total=$((fail_count + extra_count))

if [ "$fail_total" -gt 0 ]; then
  user_unique=$(printf "%s" "$user_list" | awk 'NF' | sort -u)
  user_count=$(printf "%s" "$user_unique" | grep -c . || true)
  if [ "$user_count" -eq 1 ]; then
    user_summary=$(printf "%s" "$user_unique")
  elif [ "$user_count" -gt 1 ]; then
    user_summary="multiple"
  else
    user_summary="unknown"
  fi

  if [ "$invalid_seen" -eq 1 ] && [ "$valid_seen" -eq 1 ]; then
    validity="mixed"
  elif [ "$invalid_seen" -eq 1 ]; then
    validity="invalid"
  else
    validity="valid"
  fi

  ip_summary=$(printf "%s" "$ip_list" | awk 'NF' | sort -u | paste -sd ", " -)
  [ -z "$ip_summary" ] && ip_summary="unknown"

  port_summary=$(printf "%s" "$port_list" | awk 'NF' | sort -u | paste -sd ", " -)
  [ -z "$port_summary" ] && port_summary="unknown"

  method_summary=$(printf "%s" "$method_list" | awk 'NF' | sort -u)
  method_count=$(printf "%s" "$method_summary" | grep -c . || true)
  if [ "$method_count" -eq 1 ]; then
    method_summary=$(printf "%s" "$method_summary")
  elif [ "$method_count" -gt 1 ]; then
    method_summary="multiple"
  else
    method_summary="unknown"
  fi

  if [ -n "$earliest_ts" ] && [ -n "$latest_ts" ]; then
    start_date=$(printf "%s\n" "$earliest_ts" | awk '{print $1" "$2}')
    end_date=$(printf "%s\n" "$latest_ts" | awk '{print $1" "$2}')
    start_time=$(printf "%s\n" "$earliest_ts" | awk '{print $3}')
    end_time=$(printf "%s\n" "$latest_ts" | awk '{print $3}')
    if [ "$start_date" = "$end_date" ]; then
      window="$start_date $start_time → $end_time"
    else
      window="$earliest_ts → $latest_ts"
    fi
    if [ -n "$earliest_epoch" ] && [ -n "$latest_epoch" ]; then
      diff=$((latest_epoch - earliest_epoch))
      if [ "$diff" -ge 0 ]; then
        window="$window (${diff}s)"
      fi
    fi
  else
    window="(unknown)"
  fi

  msg=$(printf "SSH ALERT · FAILED LOGINS\n────────────────────────\nHost    : %s\nUser    : %s (%s)\nCount   : %s failed attempts\nSource  : %s\nWindow  : %s\nMethod  : %s\nPort    : %s (seen)\n\nTimeline\n%s" "$(hostname)" "$user_summary" "$validity" "$fail_total" "$ip_summary" "$window" "$method_summary" "$port_summary" "${timeline:-• (no detailed lines)\n}")

  set_state "SSH_LOGIN.status" "WARN"
  log_alert "SSH_LOGIN" "WARN" "$msg"
  send_email "[Pi Monitor] SSH_LOGIN WARN" "$msg"
else
  check_and_alert "SSH_LOGIN" "OK" "No failed SSH logins since last check"
fi

set_state "login.last" "$now"
# Filesystem errors (kernel log)
last_fs=$(get_state "fs.last" 0)
if [ "$last_fs" -gt 0 ]; then
  fs_err_lines=$(journalctl -k --since "@${last_fs}" 2>/dev/null | grep -Ei "EXT4-fs error|EXT4-fs warning|Buffer I/O error|I/O error|XFS|BTRFS|FAT-fs" || true)
  fs_err_recent=$(printf "%s\n" "$fs_err_lines" | grep -c . || true)
  if [ "$fs_err_recent" -gt 0 ]; then
    fs_err_total=$((fs_err_total + fs_err_recent))
    msg=$(printf "Filesystem errors: %s new\n\nKernel errors since last check:\n%s" "$fs_err_recent" "$fs_err_lines")
    check_and_alert "FS" "CRIT" "$msg"
  else
    check_and_alert "FS" "OK" "No new filesystem errors"
  fi
else
  check_and_alert "FS" "OK" "Filesystem check initialized"
fi
set_state "fs.error_total" "$fs_err_total"
set_state "fs.last" "$now"

# SSL expiry check (daily)
last_ssl=$(get_state "ssl.last" 0)
if [ $((now - last_ssl)) -ge "$SSL_CHECK_INTERVAL" ]; then
  end_date=$(echo | openssl s_client -connect "$SSL_HOST:443" -servername "$SSL_HOST" 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
  if [ -n "$end_date" ]; then
    end_ts=$(date -d "$end_date" +%s 2>/dev/null || echo 0)
    if [ "$end_ts" -gt 0 ]; then
      days_left=$(( (end_ts - now) / 86400 ))
      if [ "$days_left" -le "$SSL_CRIT_DAYS" ]; then
        check_and_alert "SSL" "CRIT" "Cert expires in ${days_left} days"
      elif [ "$days_left" -le "$SSL_WARN_DAYS" ]; then
        check_and_alert "SSL" "WARN" "Cert expires in ${days_left} days"
      else
        check_and_alert "SSL" "OK" "Cert expires in ${days_left} days"
      fi
    fi
  fi
  set_state "ssl.last" "$now"
fi

# Metrics sample every 5 minutes
last_metric=$(get_state "metrics.last" 0)
if [ $((now - last_metric)) -ge "$METRIC_INTERVAL" ]; then
  ts=$(date +%Y-%m-%dT%H:%M:%S)
  temp_val=${temp_c:-0}
  load_val=${load1:-0}
  ram_val=${ram_used_pct:-0}
  swap_val=${swap_used_pct:-0}
  disk_val=${root_use:-0}
  echo "$ts,$temp_val,$load_val,$ram_val,$swap_val,$disk_val" >> "$METRICS_DIR/metrics.csv"
  set_state "metrics.last" "$now"
fi

# Prometheus textfile metrics (for Grafana)
textfile_dir="/srv/monitoring/metrics/textfile"
textfile_tmp="$textfile_dir/monitor.prom.tmp"
textfile_out="$textfile_dir/monitor.prom"
mkdir -p "$textfile_dir"

# Ping metrics
ping_latency_lines=""
ping_loss_lines=""
for target in "${PING_TARGETS[@]}"; do
  ping_out=$(ping -c 2 -W 2 -q "$target" 2>/dev/null || true)
  loss=100
  avg=0
  if [ -n "$ping_out" ]; then
    loss=$(echo "$ping_out" | awk -F',' '/packet loss/ {print $3}' | awk '{print $1}' | tr -d '%')
    avg=$(echo "$ping_out" | awk -F'/' '/rtt/ {print $5}')
  fi
  loss=${loss:-100}
  avg=${avg:-0}
  printf -v ping_latency_lines '%s%s\n' "$ping_latency_lines" "pi_ping_latency_ms{target=\"$target\"} $avg"
  printf -v ping_loss_lines '%s%s\n' "$ping_loss_lines" "pi_ping_loss_pct{target=\"$target\"} $loss"
done

# Network bandwidth metrics
net_rx_lines=""
net_tx_lines=""
for iface_path in /sys/class/net/*; do
  iface=$(basename "$iface_path")
  case "$iface" in
    lo|docker*|veth*|br-*|ifb*|tun* )
      continue
      ;;
  esac
  rx=$(cat "$iface_path/statistics/rx_bytes")
  tx=$(cat "$iface_path/statistics/tx_bytes")
  state_file="$STATE_DIR/net/$iface"
  rx_rate=0
  tx_rate=0
  if [ -f "$state_file" ]; then
    read -r prev_ts prev_rx prev_tx < "$state_file" || true
    if [ -n "${prev_ts:-}" ] && [ "$now" -gt "$prev_ts" ] && [ "$rx" -ge "${prev_rx:-0}" ] && [ "$tx" -ge "${prev_tx:-0}" ]; then
      dt=$((now - prev_ts))
      if [ "$dt" -gt 0 ]; then
        rx_rate=$(( (rx - prev_rx) / dt ))
        tx_rate=$(( (tx - prev_tx) / dt ))
      fi
    fi
  fi
  printf "%s %s %s\n" "$now" "$rx" "$tx" > "$state_file"
  printf -v net_rx_lines '%s%s\n' "$net_rx_lines" "pi_net_rx_bytes_per_sec{iface=\"$iface\"} $rx_rate"
  printf -v net_tx_lines '%s%s\n' "$net_tx_lines" "pi_net_tx_bytes_per_sec{iface=\"$iface\"} $tx_rate"
done

# Service status metrics
service_lines=""
for svc in "${SERVICES[@]}"; do
  svc_up=0
  if systemctl is-active --quiet "$svc"; then
    svc_up=1
  fi
  printf -v service_lines '%s%s\n' "$service_lines" "pi_service_up{service=\"$svc\"} $svc_up"
done

# Container status metrics
container_lines=""
if command -v docker >/dev/null 2>&1; then
  all_containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)
  running_containers=$(docker ps --format '{{.Names}}' 2>/dev/null || true)
  for c in $all_containers; do
    c_up=0
    if echo "$running_containers" | grep -qw "$c"; then
      c_up=1
    fi
    printf -v container_lines '%s%s\n' "$container_lines" "pi_container_up{container=\"$c\"} $c_up"
  done
fi

throttled_flag=0
if [ "${throttled_hex:-0x0}" != "0x0" ]; then
  throttled_flag=$throttled_history
fi

cat > "$textfile_tmp" <<EOF
# HELP pi_cpu_temp_c CPU temperature in Celsius
# TYPE pi_cpu_temp_c gauge
pi_cpu_temp_c ${temp_c:-0}
# HELP pi_load1 1-minute load average
# TYPE pi_load1 gauge
pi_load1 ${load1:-0}
# HELP pi_ram_used_pct RAM used percent
# TYPE pi_ram_used_pct gauge
pi_ram_used_pct ${ram_used_pct:-0}
# HELP pi_swap_used_pct Swap used percent
# TYPE pi_swap_used_pct gauge
pi_swap_used_pct ${swap_used_pct:-0}
# HELP pi_disk_used_pct Root disk used percent
# TYPE pi_disk_used_pct gauge
pi_disk_used_pct ${root_use:-0}
# HELP pi_throttled Power throttling detected since boot (1=yes, 0=no)
# TYPE pi_throttled gauge
pi_throttled ${throttled_flag}
# HELP pi_throttled_current Power throttling currently detected (1=yes, 0=no)
# TYPE pi_throttled_current gauge
pi_throttled_current ${throttled_current}
# HELP pi_throttled_history Power throttling detected since boot (1=yes, 0=no)
# TYPE pi_throttled_history gauge
pi_throttled_history ${throttled_history}
# HELP pi_ping_latency_ms Ping average latency in milliseconds
# TYPE pi_ping_latency_ms gauge
${ping_latency_lines}# HELP pi_ping_loss_pct Ping packet loss percent
# TYPE pi_ping_loss_pct gauge
${ping_loss_lines}# HELP pi_net_rx_bytes_per_sec Receive rate in bytes per second
# TYPE pi_net_rx_bytes_per_sec gauge
${net_rx_lines}# HELP pi_net_tx_bytes_per_sec Transmit rate in bytes per second
# TYPE pi_net_tx_bytes_per_sec gauge
${net_tx_lines}# HELP pi_service_up Service status (1=up, 0=down)
# TYPE pi_service_up gauge
${service_lines}# HELP pi_container_up Container status (1=up, 0=down)
# TYPE pi_container_up gauge
${container_lines}# HELP pi_ssh_failed_logins_window Failed SSH logins in window
# TYPE pi_ssh_failed_logins_window gauge
pi_ssh_failed_logins_window ${ssh_fail:-0}
# HELP pi_fs_error_recent New filesystem errors since last check
# TYPE pi_fs_error_recent gauge
pi_fs_error_recent ${fs_err_recent:-0}
# HELP pi_fs_error_total Total filesystem errors since monitor start
# TYPE pi_fs_error_total gauge
pi_fs_error_total ${fs_err_total:-0}
# HELP pi_smart_health_ok SMART overall health (1=pass, 0=fail)
# TYPE pi_smart_health_ok gauge
pi_smart_health_ok ${smart_health_ok}
# HELP pi_smart_realloc SMART realloc sector count
# TYPE pi_smart_realloc gauge
pi_smart_realloc ${smart_realloc}
# HELP pi_smart_pending SMART pending sector count
# TYPE pi_smart_pending gauge
pi_smart_pending ${smart_pending}
# HELP pi_smart_offline SMART offline uncorrectable count
# TYPE pi_smart_offline gauge
pi_smart_offline ${smart_offline}
# HELP pi_smart_crc SMART CRC error count
# TYPE pi_smart_crc gauge
pi_smart_crc ${smart_crc}
# HELP pi_smart_temp_c SMART temperature in Celsius
# TYPE pi_smart_temp_c gauge
pi_smart_temp_c ${smart_temp}
EOF
mv "$textfile_tmp" "$textfile_out"

# Monthly report (first day, after 00:05 local time)
if [ "$(date +%d)" = "01" ] && [ "$(date +%H)" = "00" ]; then
  minute=$(date +%M)
  if [ "$minute" -ge 5 ]; then
    current_month=$(date +%Y-%m)
    last_report=$(get_state "report.month" "")
    if [ "$last_report" != "$current_month" ]; then
      prev_month=$(date -d "last month" +%Y-%m)
      if [ -x /srv/monitoring/bin/monthly-report.sh ]; then
        /srv/monitoring/bin/monthly-report.sh "$prev_month" >/dev/null 2>&1 || true
      fi
      report_dir="/srv/monitoring/reports/$prev_month"
      report_txt="$(cat "$report_dir/report.txt" 2>/dev/null || echo "No report data for $prev_month")"
      alert_count=$(grep "^\[$prev_month" "$LOG_DIR/alerts.log" 2>/dev/null | wc -l || true)
      ssh_alerts=$(grep "^\[$prev_month" "$LOG_DIR/alerts.log" 2>/dev/null | grep "SSH_LOGIN" | wc -l || true)
      body="Monthly report for $prev_month\n\n$report_txt\n\nAlerts: $alert_count\nSSH login alerts: $ssh_alerts\n"
      if [ -x /srv/monitoring/bin/send-report.py ]; then
        body_file=$(mktemp)
        printf "%s" "$body" > "$body_file"
        /srv/monitoring/bin/send-report.py \
          --to "$TO_EMAIL" \
          --subject "[Pi Monthly Report] $prev_month" \
          --body-file "$body_file" \
          --attach "$report_dir/temperature.png" \
          --attach "$report_dir/load.png" \
          --attach "$report_dir/memory.png" \
          --attach "$report_dir/throttling.png" \
          --attach "$report_dir/ping-latency.png" \
          --attach "$report_dir/ping-loss.png" \
          --attach "$report_dir/bandwidth.png" \
          --attach "$report_dir/services.png" \
          --attach "$report_dir/fs-errors.png" \
          --attach "$report_dir/smart.png"
        rm -f "$body_file"
      else
        send_email "[Pi Monthly Report] $prev_month" "$body"
      fi
      set_state "report.month" "$current_month"
    fi
  fi
fi
