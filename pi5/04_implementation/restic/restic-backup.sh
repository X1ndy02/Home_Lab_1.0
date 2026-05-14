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

    last_start=$(grep "Starting restic backup" "$log_file" 2>/dev/null | tail -n 1 || true)
    last_end=$(grep "Backup completed" "$log_file" 2>/dev/null | tail -n 1 || true)
    files=$(grep "^Files:" "$log_file" 2>/dev/null | tail -n 1 || true)
    dirs=$(grep "^Dirs:" "$log_file" 2>/dev/null | tail -n 1 || true)
    added=$(grep "^Added to the repository:" "$log_file" 2>/dev/null | tail -n 1 || true)
    processed=$(grep "^processed " "$log_file" 2>/dev/null | tail -n 1 || true)
    snapshot=$(grep "^snapshot " "$log_file" 2>/dev/null | tail -n 1 || true)
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

r2_summary_text() {
  local r2_log_file="$1"
  local copy_result="${2:-unknown}"
  local rotate_result="${3:-unknown}"
  local snapshot_count="${4:-N/A}"

  printf 'Offsite Backup (Cloudflare R2) Summary\n'
  printf '======================================\n'
  printf 'Copy              : %s\n' "$copy_result"
  printf 'Rotation          : %s\n' "$rotate_result"
  printf 'Snapshots in R2   : %s\n' "$snapshot_count"

  if [ -r "$r2_log_file" ]; then
    local start_time end_time snap_id packs_line remove_count

    start_time=$(grep "Starting R2 offsite copy" "$r2_log_file" 2>/dev/null | head -1 | awk '{print $1}' || true)
    end_time=$(grep "R2 rotation complete" "$r2_log_file" 2>/dev/null | tail -1 | awk '{print $1}' || true)
    snap_id=$(grep "^snapshot .* of \[" "$r2_log_file" 2>/dev/null | head -1 | awk '{print $2}' || true)
    packs_line=$(grep "packs copied" "$r2_log_file" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
    remove_count=$(grep "^remove [0-9]* snapshots:" "$r2_log_file" 2>/dev/null | tail -1 | awk '{print $2}' || true)

    printf '\nTimeline:\n'
    [ -n "$start_time" ] && printf '  Started   : %s\n' "$start_time"
    [ -n "$end_time"   ] && printf '  Completed : %s\n' "$end_time"

    printf '\nCopy details:\n'
    [ -n "$snap_id"    ] && printf '  Snapshot  : %s\n' "$snap_id"
    [ -n "$packs_line" ] && printf '  Progress  : %s\n' "$packs_line"

    printf '\nRotation details:\n'
    printf '  Kept      : %s snapshot(s)\n' "${snapshot_count:-N/A}"
    [ -n "$remove_count" ] && printf '  Pruned    : %s old snapshot(s)\n' "$remove_count"

    # Print the kept-snapshots table from forget output
    if grep -q "^ID.*Time.*Host" "$r2_log_file" 2>/dev/null; then
      printf '\nKept snapshots:\n'
      awk '/^ID[[:space:]]+Time/{p=1} p{print} /^[0-9]+ snapshots$/{p=0}' "$r2_log_file"
    fi
  fi
}

send_r2_mail() {
  local subject="$1"
  local body="$2"
  local r2_log_file="$3"
  local copy_result="$4"
  local rotate_result="$5"
  local snapshot_count="$6"
  local boundary="====restic_$(date +%s%N)===="
  local tmp_dir tmp_log tmp_summary tmp_events tmp_body

  if ! command -v sendmail >/dev/null 2>&1; then
    return 0
  fi

  tmp_dir=$(mktemp -d)
  tmp_log="$tmp_dir/r2-offsite.log"
  tmp_summary="$tmp_dir/r2-summary.log"
  tmp_events="$tmp_dir/r2-events.log"
  tmp_body="$tmp_dir/r2-email.txt"

  if [ -r "$r2_log_file" ]; then
    cp "$r2_log_file" "$tmp_log"
  else
    printf '(no R2 log available)\n' > "$tmp_log"
  fi

  {
    r2_summary_text "$r2_log_file" "$copy_result" "$rotate_result" "$snapshot_count"
  } > "$tmp_summary"

  {
    grep -iE "FAILED|Fatal:|error:" "$r2_log_file" 2>/dev/null || true
  } > "$tmp_events"

  printf '%s\n' "$body" > "$tmp_body"
  chmod 755 "$tmp_dir"
  chmod 644 "$tmp_log" "$tmp_summary" "$tmp_events" "$tmp_body"

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
    printf 'Content-Type: text/plain; name="r2-offsite.log"\n'
    printf 'Content-Transfer-Encoding: base64\n'
    printf 'Content-Disposition: attachment; filename="r2-offsite.log"\n\n'
    base64 "$tmp_log"
    printf '\n--%s\n' "$boundary"
    printf 'Content-Type: text/plain; name="r2-summary.log"\n'
    printf 'Content-Transfer-Encoding: base64\n'
    printf 'Content-Disposition: attachment; filename="r2-summary.log"\n\n'
    base64 "$tmp_summary"
    printf '\n--%s\n' "$boundary"
    printf 'Content-Type: text/plain; name="r2-events.log"\n'
    printf 'Content-Transfer-Encoding: base64\n'
    printf 'Content-Disposition: attachment; filename="r2-events.log"\n\n'
    base64 "$tmp_events"
    printf '\n--%s--\n' "$boundary"
  } | sendmail -t || log "WARNING: sendmail failed for: $subject"
  archive_backup_mail "$subject" "$tmp_body" "$tmp_log" "$tmp_summary" "$tmp_events" || true

  rm -rf "$tmp_dir"
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
    } | sendmail -t || log "WARNING: sendmail failed for: $subject"
    archive_backup_mail "$subject" "$tmp_body" "$tmp_full" "$tmp_summary" "$tmp_events" || true

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
    } | sendmail -t || log "WARNING: sendmail failed for: $subject"
    archive_backup_mail "$subject" "$tmp_body" || true

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
  send_mail "Local Backup — TEST" "$(summary_counts "$tmp_log")" "$tmp_log"
  rm -rf "$tmp_dir"
  exit 0
fi

if ! mountpoint -q /mnt/backup; then
  log "Backup mount not present: /mnt/backup"
  send_mail "Local Backup — FAILED: /mnt/backup not mounted" "$(summary_counts "$RESTIC_LOG")" "$RESTIC_LOG"
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
  send_ntfy "Local Backup — FAILED" urgent
  send_mail "Local Backup — FAILED" "$(summary_counts "$RESTIC_LOG")" "$RESTIC_LOG"
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
    init_output=$(
      AWS_ACCESS_KEY_ID="$RESTIC_R2_ACCESS_KEY_ID" \
      AWS_SECRET_ACCESS_KEY="$RESTIC_R2_SECRET_ACCESS_KEY" \
      restic --repo "$RESTIC_R2_REPOSITORY" \
             --password-file "$RESTIC_PASSWORD_FILE" \
             init 2>&1
    ) || {
      # Tolerate "already initialized" — cat config can fail on transient network errors
      if printf "%s\n" "$init_output" | grep -q "already initialized"; then
        log "R2 repo already initialized (cat config failed transiently) — continuing"
      else
        printf "%s\n" "$init_output" | tee -a "$RESTIC_LOG" "$r2_log"
        log "R2 restic init FAILED"
        exit 1
      fi
    }
    printf "%s\n" "$init_output" | tee -a "$RESTIC_LOG" "$r2_log"
  fi

  mapfile -t r2_snap_ids < <(
    restic --repo "$RESTIC_REPOSITORY" \
           --password-file "$RESTIC_PASSWORD_FILE" \
           snapshots --latest "${RESTIC_R2_KEEP_LAST:-2}" --compact 2>/dev/null \
      | grep '^[0-9a-f]' | awk '{print $1}'
  )

  r2_copy_status=0
  r2_copy_output=$(
    AWS_ACCESS_KEY_ID="$RESTIC_R2_ACCESS_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$RESTIC_R2_SECRET_ACCESS_KEY" \
    restic copy \
      --from-repo "$RESTIC_REPOSITORY" \
      --from-password-file "$RESTIC_PASSWORD_FILE" \
      --repo "$RESTIC_R2_REPOSITORY" \
      --password-file "$RESTIC_PASSWORD_FILE" \
      "${r2_snap_ids[@]}" 2>&1
  ) || r2_copy_status=$?
  printf '%s\n' "$r2_copy_output" >> "$RESTIC_LOG"
  printf '%s\n' "$r2_copy_output" >> "$r2_log"

  if [ "$r2_copy_status" -ne 0 ]; then
    log "R2 offsite copy FAILED"
    printf '%s R2 offsite copy FAILED\n' "$(date -Is)" >> "$r2_log"
    r2_copy_result="FAILED"
    r2_rotate_result="skipped (copy failed)"
    send_ntfy "Offsite Backup — FAILED: copy" high
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
      send_ntfy "Offsite Backup — FAILED: rotation" high
      # Still query count so the email shows how many snapshots remain in R2
      r2_snapshot_count=$(
        AWS_ACCESS_KEY_ID="$RESTIC_R2_ACCESS_KEY_ID" \
        AWS_SECRET_ACCESS_KEY="$RESTIC_R2_SECRET_ACCESS_KEY" \
        restic snapshots \
          --repo "$RESTIC_R2_REPOSITORY" \
          --password-file "$RESTIC_PASSWORD_FILE" \
          --compact 2>/dev/null | grep -c '^[0-9a-f]' || echo "?"
      )
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

local_subject="Local Backup — Success"
if [ -n "$usage_pct" ] && [ "$usage_pct" -ge 80 ]; then
  local_subject="Local Backup — WARNING: disk ${usage_pct}%"
  log "Backup WARNING: disk usage ${usage_pct}%"
  send_ntfy "Local Backup — WARNING: disk ${usage_pct}%" high
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
    r2_subject="Offsite Backup — FAILED"
    r2_body="$(cat <<REPORT
Offsite Backup (Cloudflare R2) — $(date '+%A %d %B %Y, %H:%M %Z')
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

Logs attached.
REPORT
)"
  else
    r2_subject="Offsite Backup — Success"
    r2_body="$(cat <<REPORT
Offsite Backup (Cloudflare R2) — $(date '+%A %d %B %Y, %H:%M %Z')
============================================================
  Copy            : ${r2_copy_result}
  Rotation        : ${r2_rotate_result}
  Latest snapshot : ${r2_latest}
  Snapshots kept  : ${r2_snapshot_count}

Logs attached.
REPORT
)"
  fi

  send_r2_mail "$r2_subject" "$r2_body" "$r2_log" "$r2_copy_result" "$r2_rotate_result" "$r2_snapshot_count"
  rm -f "$r2_log"
fi
