#!/usr/bin/env bash
set -euo pipefail

if [ ! -r /etc/restic/backup.env ]; then
  echo "Missing /etc/restic/backup.env" >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/restic/backup.env
export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE RESTIC_CACHE_DIR
export RESTIC_R2_REPOSITORY RESTIC_R2_ACCESS_KEY_ID RESTIC_R2_SECRET_ACCESS_KEY RESTIC_R2_KEEP_LAST

log() {
  printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$RESTIC_LOG"
}

summary_counts() {
  local log_file="${1:-$RESTIC_LOG}"
  if [ -r "$log_file" ]; then
    local failures warnings successes
    failures=$(grep -c "Backup failed" "$log_file" 2>/dev/null || true)
    warnings=$(grep -c "Backup WARNING" "$log_file" 2>/dev/null || true)
    successes=$(grep -c "Backup completed" "$log_file" 2>/dev/null || true)
    printf 'Failures: %s\n' "${failures:-0}"
    printf 'Warnings: %s\n' "${warnings:-0}"
    printf 'Successes: %s\n' "${successes:-0}"
  else
    printf 'Failures: 0\nWarnings: 0\nSuccesses: 0\n'
  fi
}

summary_text() {
  local log_file="${1:-$RESTIC_LOG}"
  if [ -r "$log_file" ]; then
    local failures warnings successes
    local last_start last_end files dirs added processed snapshot usage

    failures=$(grep -c "Backup failed" "$log_file" 2>/dev/null || true)
    warnings=$(grep -c "Backup WARNING" "$log_file" 2>/dev/null || true)
    successes=$(grep -c "Backup completed" "$log_file" 2>/dev/null || true)

    last_start=$(grep "Starting restic backup" "$log_file" 2>/dev/null | tail -n 1)
    last_end=$(grep "Backup completed" "$log_file" 2>/dev/null | tail -n 1)
    files=$(grep "^Files:" "$log_file" 2>/dev/null | tail -n 1)
    dirs=$(grep "^Dirs:" "$log_file" 2>/dev/null | tail -n 1)
    added=$(grep "^Added to the repository:" "$log_file" 2>/dev/null | tail -n 1)
    processed=$(grep "^processed " "$log_file" 2>/dev/null | tail -n 1)
    snapshot=$(grep "^snapshot " "$log_file" 2>/dev/null | tail -n 1)
    usage=$(df -h /mnt/backup 2>/dev/null | awk 'NR==2 {print $3" used of "$2" ("$5")"}')

    printf 'Summary (from log):\n'
    printf 'Failures: %s\n' "${failures:-0}"
    printf 'Warnings: %s\n' "${warnings:-0}"
    printf 'Successes: %s\n' "${successes:-0}"

    printf '\nLast run details:\n'
    if [ -n "$last_start" ]; then printf 'Start: %s\n' "$last_start"; else printf 'Start: N/A\n'; fi
    if [ -n "$last_end" ]; then printf 'End: %s\n' "$last_end"; else printf 'End: N/A\n'; fi
    if [ -n "$files" ]; then printf '%s\n' "$files"; else printf 'Files: N/A\n'; fi
    if [ -n "$dirs" ]; then printf '%s\n' "$dirs"; else printf 'Dirs: N/A\n'; fi
    if [ -n "$added" ]; then printf '%s\n' "$added"; else printf 'Added to the repository: N/A\n'; fi
    if [ -n "$processed" ]; then printf '%s\n' "$processed"; else printf 'Processed: N/A\n'; fi
    if [ -n "$snapshot" ]; then printf '%s\n' "$snapshot"; else printf 'Snapshot: N/A\n'; fi
    if [ -n "$usage" ]; then printf 'Disk usage: %s\n' "$usage"; else printf 'Disk usage: N/A\n'; fi
  fi
}

archive_backup_mail() {
  local subject="$1"
  local body_file="$2"
  shift 2
  local repo_root="/home/xindy/Desktop/Home_Lab_1.0"
  local archive_script="$repo_root/scripts/smtp_archive.py"
  local token_file="/home/xindy/Desktop/github_token.txt"
  local timestamp archive_output archive_status
  local -a cmd

  if [ "${RESTIC_SKIP_ARCHIVE:-0}" = "1" ]; then
    return 0
  fi

  timestamp=$(date -Is)
  cmd=(
    sudo -u xindy
    env
    "SMTP_ARCHIVE_GITHUB_TOKEN_FILE=$token_file"
    python3
    "$archive_script"
    --repo
    "$repo_root"
    --source
    backup_status
    --timestamp
    "$timestamp"
    --from-addr
    "$RESTIC_NOTIFY_FROM"
    --to-addr
    "$RESTIC_NOTIFY_TO"
    --subject
    "$subject"
    --body-file
    "$body_file"
    --push
  )

  while [ "$#" -gt 0 ]; do
    if [ -r "$1" ]; then
      cmd+=(--attach "$1")
    fi
    shift
  done

  set +e
  archive_output="$("${cmd[@]}" 2>&1)"
  archive_status=$?
  set -e

  if [ "$archive_status" -ne 0 ]; then
    log "SMTP archive push failed: $archive_output"
    RESTIC_SKIP_ARCHIVE=1 send_mail \
      "Git push failed" \
      "A git push did not complete successfully for the backup email archive.

Original subject: $subject
Repository: $repo_root

Error:
$archive_output" \
      "$RESTIC_LOG"
  fi
}

send_ntfy() {
  local subject="$1"
  local priority="${2:-default}"
  curl -s --max-time 5 \
    -H "Title: $subject" \
    -H "Priority: $priority" \
    -d "$subject" \
    "http://10.244.10.4:8080/rootnode-7996ee61" >/dev/null 2>&1 || true
}

send_mail() {
  local subject="$1"
  local body="$2"
  local log_file="${3:-$RESTIC_LOG}"
  local boundary="====restic_$(date +%s%N)===="
  local tmp_dir tmp_full tmp_summary tmp_events tmp_body

  if ! command -v sendmail >/dev/null 2>&1; then
    return 0
  fi

  if [ -r "$log_file" ]; then
    tmp_dir=$(mktemp -d)
    tmp_full="$tmp_dir/restic-backup.log"
    tmp_summary="$tmp_dir/restic-summary.log"
    tmp_events="$tmp_dir/restic-events.log"
    tmp_body="$tmp_dir/restic-email.txt"

    cp "$log_file" "$tmp_full"
    {
      summary_text "$log_file"
    } > "$tmp_summary"
    {
      grep "Backup failed" "$log_file" 2>/dev/null || true
      grep "Backup WARNING" "$log_file" 2>/dev/null || true
    } > "$tmp_events"
    printf '%s\n' "$body" > "$tmp_body"
    chmod 755 "$tmp_dir"
    chmod 644 "$tmp_full" "$tmp_summary" "$tmp_events" "$tmp_body"

    {
      printf 'From: %s\n' "$RESTIC_NOTIFY_FROM"
      printf 'To: %s\n' "$RESTIC_NOTIFY_TO"
      printf 'Subject: %s\n' "$subject"
      printf 'MIME-Version: 1.0\n'
      printf 'Content-Type: multipart/mixed; boundary="%s"\n' "$boundary"
      printf '\n--%s\n' "$boundary"
      printf 'Content-Type: text/plain; charset="utf-8"\n'
      printf 'Content-Transfer-Encoding: 7bit\n\n'
      printf '%s\n' "$body"
      printf '\n--%s\n' "$boundary"
      printf 'Content-Type: text/plain; name="restic-backup.log"\n'
      printf 'Content-Transfer-Encoding: base64\n'
      printf 'Content-Disposition: attachment; filename="restic-backup.log"\n\n'
      base64 "$tmp_full"
      printf '\n--%s\n' "$boundary"
      printf 'Content-Type: text/plain; name="restic-summary.log"\n'
      printf 'Content-Transfer-Encoding: base64\n'
      printf 'Content-Disposition: attachment; filename="restic-summary.log"\n\n'
      base64 "$tmp_summary"
      printf '\n--%s\n' "$boundary"
      printf 'Content-Type: text/plain; name="restic-events.log"\n'
      printf 'Content-Transfer-Encoding: base64\n'
      printf 'Content-Disposition: attachment; filename="restic-events.log"\n\n'
      base64 "$tmp_events"
      printf '\n--%s--\n' "$boundary"
    } | sendmail -t
    archive_backup_mail "$subject" "$tmp_body" "$tmp_full" "$tmp_summary" "$tmp_events"

    rm -rf "$tmp_dir"
  else
    tmp_dir=$(mktemp -d)
    tmp_body="$tmp_dir/restic-email.txt"
    printf '%s\n' "$body" > "$tmp_body"
    chmod 755 "$tmp_dir"
    chmod 644 "$tmp_body"

    {
      printf 'From: %s\n' "$RESTIC_NOTIFY_FROM"
      printf 'To: %s\n' "$RESTIC_NOTIFY_TO"
      printf 'Subject: %s\n' "$subject"
      printf 'MIME-Version: 1.0\n'
      printf 'Content-Type: text/plain; charset="utf-8"\n'
      printf 'Content-Transfer-Encoding: 7bit\n\n'
      printf '%s\n' "$body"
    } | sendmail -t
    archive_backup_mail "$subject" "$tmp_body"

    rm -rf "$tmp_dir"
  fi
}

if [ "${RESTIC_NOTIFY_TEST:-}" = "1" ]; then
  tmp_dir=$(mktemp -d)
  tmp_log="$tmp_dir/restic-test.log"
  cat > "$tmp_log" <<'TESTLOG'
2026-01-27T21:00:00+11:00 Starting restic backup
Files:        10 new,  2 changed, 100 unmodified
Dirs:          1 new,  1 changed,  20 unmodified
Added to the repository: 12.345 MiB (4.321 MiB stored)
processed 112 files, 123.456 MiB in 0:03
snapshot deadbeef saved
2026-01-27T21:00:03+11:00 Backup completed
2026-01-27T21:00:04+11:00 Backup WARNING: disk usage 85%
2026-01-27T21:00:05+11:00 Backup failed
TESTLOG
  send_mail "Backup TEST" "$(summary_counts "$tmp_log")" "$tmp_log"
  rm -rf "$tmp_dir"
  exit 0
fi

if ! mountpoint -q /mnt/backup; then
  log "Backup mount not present: /mnt/backup"
  send_mail "Backup FAILED: /mnt/backup not mounted" "$(summary_counts "$RESTIC_LOG")" "$RESTIC_LOG"
  exit 1
fi

mkdir -p "$RESTIC_REPOSITORY"

if ! restic cat config >/dev/null 2>&1; then
  log "Initializing restic repo at $RESTIC_REPOSITORY"
  restic init
fi

log "Starting restic backup"
backup_output=$(restic backup / --exclude-file "$RESTIC_EXCLUDES" 2>&1)
backup_status=$?
printf '%s\n' "$backup_output" >> "$RESTIC_LOG"

if [ "$backup_status" -ne 0 ]; then
  log "Backup failed"
  send_ntfy "Backup FAILED: $RESTIC_REPOSITORY" urgent
  send_mail "Backup FAILED" "$(summary_counts "$RESTIC_LOG")" "$RESTIC_LOG"
  exit "$backup_status"
fi

forget_output=$(restic forget --keep-last "$RESTIC_KEEP_LAST" --prune 2>&1 || true)
printf '%s\n' "$forget_output" >> "$RESTIC_LOG"

snapshots=$(restic snapshots --latest "$RESTIC_KEEP_LAST" 2>/dev/null || true)
latest_snapshot=$(printf '%s\n' "$snapshots" | tail -n 1)

usage_pct=$(df -P /mnt/backup | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
usage_line=$(df -h /mnt/backup | awk 'NR==2 {print $3" used of "$2" ("$5")"}')

log "Backup completed"

# Track R2 status for the report
r2_copy_result="skipped (not configured)"
r2_rotate_result="skipped"
r2_snapshot_count="N/A"
r2_log=$(mktemp)

# Copy new snapshots to Cloudflare R2 offsite repo
if [ -n "${RESTIC_R2_REPOSITORY:-}" ] && [ -n "${RESTIC_R2_ACCESS_KEY_ID:-}" ]; then
  log "Starting R2 offsite copy"
  printf '%s Starting R2 offsite copy\n' "$(date -Is)" >> "$r2_log"

  # Initialize R2 repo on first run if needed
  if ! AWS_ACCESS_KEY_ID="$RESTIC_R2_ACCESS_KEY_ID" \
       AWS_SECRET_ACCESS_KEY="$RESTIC_R2_SECRET_ACCESS_KEY" \
       restic --repo "$RESTIC_R2_REPOSITORY" \
              --password-file "$RESTIC_PASSWORD_FILE" \
              cat config >/dev/null 2>&1; then
    log "Initializing R2 restic repo"
    AWS_ACCESS_KEY_ID="$RESTIC_R2_ACCESS_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$RESTIC_R2_SECRET_ACCESS_KEY" \
    restic --repo "$RESTIC_R2_REPOSITORY" \
           --password-file "$RESTIC_PASSWORD_FILE" \
           init 2>&1 | tee -a "$RESTIC_LOG" "$r2_log"
  fi

  r2_copy_status=0
  r2_copy_output=$(
    AWS_ACCESS_KEY_ID="$RESTIC_R2_ACCESS_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$RESTIC_R2_SECRET_ACCESS_KEY" \
    restic copy \
      --from-repo "$RESTIC_REPOSITORY" \
      --from-password-file "$RESTIC_PASSWORD_FILE" \
      --repo "$RESTIC_R2_REPOSITORY" \
      --password-file "$RESTIC_PASSWORD_FILE" 2>&1
  ) || r2_copy_status=$?
  printf '%s\n' "$r2_copy_output" >> "$RESTIC_LOG"
  printf '%s\n' "$r2_copy_output" >> "$r2_log"

  if [ "$r2_copy_status" -ne 0 ]; then
    log "R2 offsite copy FAILED"
    printf '%s R2 offsite copy FAILED\n' "$(date -Is)" >> "$r2_log"
    r2_copy_result="FAILED"
    r2_rotate_result="skipped (copy failed)"
    send_ntfy "R2 offsite copy FAILED" high
  else
    log "R2 offsite copy completed"
    printf '%s R2 offsite copy completed\n' "$(date -Is)" >> "$r2_log"
    r2_copy_result="Success"

    # Rotate: keep only the most recent snapshots in R2
    r2_rotate_status=0
    r2_rotate_output=$(
      AWS_ACCESS_KEY_ID="$RESTIC_R2_ACCESS_KEY_ID" \
      AWS_SECRET_ACCESS_KEY="$RESTIC_R2_SECRET_ACCESS_KEY" \
      restic forget \
        --repo "$RESTIC_R2_REPOSITORY" \
        --password-file "$RESTIC_PASSWORD_FILE" \
        --keep-last "${RESTIC_R2_KEEP_LAST:-2}" \
        --prune 2>&1
    ) || r2_rotate_status=$?
    printf '%s\n' "$r2_rotate_output" >> "$RESTIC_LOG"
    printf '%s\n' "$r2_rotate_output" >> "$r2_log"

    if [ "$r2_rotate_status" -ne 0 ]; then
      log "R2 rotation FAILED"
      printf '%s R2 rotation FAILED\n' "$(date -Is)" >> "$r2_log"
      r2_rotate_result="FAILED"
      send_ntfy "R2 rotation FAILED" high
    else
      log "R2 rotation complete (keep-last=${RESTIC_R2_KEEP_LAST:-2})"
      printf '%s R2 rotation complete\n' "$(date -Is)" >> "$r2_log"
      r2_rotate_result="Success"
      r2_snapshot_count=$(
        AWS_ACCESS_KEY_ID="$RESTIC_R2_ACCESS_KEY_ID" \
        AWS_SECRET_ACCESS_KEY="$RESTIC_R2_SECRET_ACCESS_KEY" \
        restic snapshots \
          --repo "$RESTIC_R2_REPOSITORY" \
          --password-file "$RESTIC_PASSWORD_FILE" \
          --compact 2>/dev/null | grep -c '^[0-9a-f]' || echo "?"
      )
    fi
  fi
fi

# --- Local backup email ---
local_latest=$(restic snapshots --latest 1 --compact 2>/dev/null | grep '^[0-9a-f]' | awk '{print $1, $2, $3}' || echo "N/A")

local_subject="Backup Success"
if [ -n "$usage_pct" ] && [ "$usage_pct" -ge 80 ]; then
  local_subject="Backup Success — WARNING: disk ${usage_pct}%"
  log "Backup WARNING: disk usage ${usage_pct}%"
  send_ntfy "Backup WARNING: disk usage ${usage_pct}%" high
fi

local_body="$(cat <<REPORT
Local Backup — $(date '+%A %d %B %Y, %H:%M %Z')
============================================================
  Status          : Success
  Latest snapshot : ${local_latest}
  Disk used       : ${usage_line:-N/A}

Full log attached.
REPORT
)"

send_ntfy "$local_subject" low
send_mail "$local_subject" "$local_body" "$RESTIC_LOG"

# --- R2 backup email ---
if [ -n "${RESTIC_R2_REPOSITORY:-}" ] && [ -n "${RESTIC_R2_ACCESS_KEY_ID:-}" ]; then
  r2_latest=$(
    AWS_ACCESS_KEY_ID="$RESTIC_R2_ACCESS_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$RESTIC_R2_SECRET_ACCESS_KEY" \
    restic snapshots \
      --repo "$RESTIC_R2_REPOSITORY" \
      --password-file "$RESTIC_PASSWORD_FILE" \
      --latest 1 --compact 2>/dev/null | grep '^[0-9a-f]' | awk '{print $1, $2, $3}' || echo "N/A"
  )

  r2_failed=0
  [ "${r2_copy_result}" = "FAILED" ] && r2_failed=1
  [ "${r2_rotate_result}" = "FAILED" ] && r2_failed=1

  if [ "$r2_failed" -eq 1 ]; then
    r2_subject="R2 Offsite Backup FAILED"
    r2_body="$(cat <<REPORT
R2 Offsite Backup — $(date '+%A %d %B %Y, %H:%M %Z')
============================================================
  Copy            : ${r2_copy_result}
  Rotation        : ${r2_rotate_result}
  Latest snapshot : ${r2_latest}
  Snapshots kept  : ${r2_snapshot_count}

------------------------------------------------------------
WHAT TO CHECK
------------------------------------------------------------
  - Check internet connectivity on rootnode
  - Verify credentials in /etc/restic/backup.env
  - Re-run: sudo /usr/local/sbin/restic-backup.sh

R2 log attached.
REPORT
)"
  else
    r2_subject="R2 Offsite Backup Success"
    r2_body="$(cat <<REPORT
R2 Offsite Backup — $(date '+%A %d %B %Y, %H:%M %Z')
============================================================
  Copy            : ${r2_copy_result}
  Rotation        : ${r2_rotate_result}
  Latest snapshot : ${r2_latest}
  Snapshots kept  : ${r2_snapshot_count}

R2 log attached.
REPORT
)"
  fi

  send_mail "$r2_subject" "$r2_body" "$r2_log"
  rm -f "$r2_log"
fi
