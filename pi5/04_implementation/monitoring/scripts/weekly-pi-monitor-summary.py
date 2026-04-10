#!/usr/bin/env python3
import argparse
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta

try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

TZ_NAME = "Australia/Sydney"
CONF_PATH = "/etc/weekly-pi-monitor-summary.conf"
PI_ALERTS_LOG = "/srv/monitoring/logs/alerts.log"
ARCHIVE_REPO = "/home/xindy/Desktop/Home_Lab_1.0"
ARCHIVE_SCRIPT = f"{ARCHIVE_REPO}/scripts/smtp_archive.py"
ARCHIVE_TOKEN_FILE = "/home/xindy/Desktop/github_token.txt"


def load_kv(path):
    cfg = {}
    if not os.path.exists(path):
        return cfg
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            cfg[k.strip()] = v.strip()
    return cfg


def now_local():
    if ZoneInfo:
        return datetime.now(ZoneInfo(TZ_NAME))
    return datetime.now()


def parse_msmtprc(path):
    if not os.path.exists(path):
        return {}
    lines = [ln.strip() for ln in open(path, "r", encoding="utf-8").read().splitlines()]
    accounts = {}
    current = None
    section = None

    for ln in lines:
        if not ln or ln.startswith("#"):
            continue
        if ln == "defaults":
            section = "defaults"
            current = None
            accounts.setdefault("_defaults", {})
            continue
        if ln.startswith("account "):
            m = re.match(r"account\s+default\s*:\s*(\S+)", ln)
            if m:
                section = "default-ref"
                accounts.setdefault("_meta", {})["default"] = m.group(1)
                current = None
                continue
            m = re.match(r"account\s+(\S+)", ln)
            if m:
                current = m.group(1)
                accounts.setdefault(current, {})
                section = "account"
                continue
        parts = ln.split(None, 1)
        if len(parts) != 2:
            continue
        key, val = parts[0], parts[1]
        if section == "account" and current:
            accounts[current][key] = val
        elif section == "defaults":
            accounts.setdefault("_defaults", {})[key] = val

    default_name = accounts.get("_meta", {}).get("default")
    acct = {}
    if accounts.get("_defaults"):
        acct.update(accounts["_defaults"])
    if default_name and default_name in accounts:
        acct.update(accounts[default_name])
    else:
        for k, v in accounts.items():
            if k not in ("_defaults", "_meta"):
                acct.update(v)
                break
    return acct


def resolve_email():
    cfg = load_kv(CONF_PATH)
    if cfg.get("TO") and cfg.get("FROM"):
        return cfg["TO"], cfg["FROM"]

    ups_cfg = load_kv("/etc/x120x/ups-notify.conf")
    to_addr = ups_cfg.get("TO")
    from_addr = ups_cfg.get("FROM")
    if to_addr and from_addr:
        return to_addr, from_addr

    fail2ban = load_kv("/etc/fail2ban/jail.local")
    to_addr = fail2ban.get("destemail")
    from_addr = fail2ban.get("sender")
    if to_addr and from_addr:
        return to_addr, from_addr

    acct = parse_msmtprc("/etc/msmtprc")
    from_addr = acct.get("from") or acct.get("user")
    to_addr = from_addr
    if to_addr and from_addr:
        return to_addr, from_addr

    host = os.uname().nodename
    return f"root@{host}", f"root@{host}"


def archive_copy(source_id, to_addr, from_addr, subject, body, attachments):
    with tempfile.TemporaryDirectory(prefix="pi-monitor-summary-") as tmpdir:
        os.chmod(tmpdir, 0o755)
        body_path = os.path.join(tmpdir, "email-body.txt")
        with open(body_path, "w", encoding="utf-8") as f:
            f.write(body)
            if not body.endswith("\n"):
                f.write("\n")
        os.chmod(body_path, 0o644)

        cmd = [
            "sudo",
            "-u",
            "xindy",
            "env",
            f"SMTP_ARCHIVE_GITHUB_TOKEN_FILE={ARCHIVE_TOKEN_FILE}",
            "python3",
            ARCHIVE_SCRIPT,
            "--repo",
            ARCHIVE_REPO,
            "--source",
            source_id,
            "--timestamp",
            datetime.now().astimezone().isoformat(),
            "--from-addr",
            from_addr,
            "--to-addr",
            to_addr,
            "--subject",
            subject,
            "--body-file",
            body_path,
            "--push",
        ]

        for name, content in attachments:
            path = os.path.join(tmpdir, name)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
                if not content.endswith("\n"):
                    f.write("\n")
            os.chmod(path, 0o644)
            cmd.extend(["--attach", path])

        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        return result.returncode, result.stdout.strip()


def send_failure_mail(to_addr, from_addr, subject, error_text):
    msg = (
        f"From: {from_addr}\n"
        f"To: {to_addr}\n"
        f"Subject: Git push failed\n"
        "MIME-Version: 1.0\n"
        "Content-Type: text/plain; charset=UTF-8\n"
        "\n"
        "A git push did not complete successfully for the Pi monitor email archive.\n\n"
        f"Original subject: {subject}\n"
        f"Repository: {ARCHIVE_REPO}\n\n"
        "Error:\n"
        f"{error_text}\n"
    )
    subprocess.run(["/usr/sbin/sendmail", "-t", "-oi"], input=msg, text=True)


def parse_iso(ts):
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    if re.match(r".*[+-]\d{4}$", ts):
        ts = ts[:-5] + ts[-5:-2] + ":" + ts[-2:]
    return datetime.fromisoformat(ts)


def fmt_ts(dt, tz):
    if dt.tzinfo and tz:
        dt = dt.astimezone(tz)
    return dt.strftime("%Y-%m-%d %H:%M %Z")


def fmt_ts_short(dt, tz):
    if dt.tzinfo and tz:
        dt = dt.astimezone(tz)
    return dt.strftime("%Y-%m-%d %H:%M")


def fmt_date(dt, tz):
    if dt.tzinfo and tz:
        dt = dt.astimezone(tz)
    return dt.strftime("%Y-%m-%d")


def fmt_time(dt, tz):
    if dt.tzinfo and tz:
        dt = dt.astimezone(tz)
    return dt.strftime("%H:%M")



def parse_arg_dt(val, tz):
    if not val:
        return None
    try:
        dt = parse_iso(val)
    except Exception:
        dt = None
    if dt is None:
        dt = datetime.fromisoformat(val)
    if dt.tzinfo is None and tz:
        dt = dt.replace(tzinfo=tz)
    return dt


def month_range(target, tz):
    year = target.year
    month = target.month
    start = datetime(year, month, 1, tzinfo=tz)
    if month == 12:
        end = datetime(year + 1, 1, 1, tzinfo=tz)
    else:
        end = datetime(year, month + 1, 1, tzinfo=tz)
    return start, end
def collect_ssh_logins(start, end, tz):
    since = start.strftime("%Y-%m-%d %H:%M:%S")
    until = end.strftime("%Y-%m-%d %H:%M:%S")
    cmd = [
        "journalctl",
        "-u",
        "ssh",
        "-u",
        "sshd",
        "--since",
        since,
        "--until",
        until,
        "--no-pager",
        "--output",
        "short-iso",
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    lines = [ln for ln in res.stdout.splitlines() if ln.strip()]

    fail_re = re.compile(
        r"Failed\s+(?P<method>[\w\-/]+)\s+for\s+(?P<invalid>invalid user\s+)?(?P<user>\S+)\s+from\s+(?P<ip>[0-9a-fA-F:.]+)\s+port\s+(?P<port>\d+)",
        re.I,
    )
    ok_re = re.compile(
        r"Accepted\s+(?P<method>[\w\-/]+)\s+for\s+(?P<invalid>invalid user\s+)?(?P<user>\S+)\s+from\s+(?P<ip>[0-9a-fA-F:.]+)\s+port\s+(?P<port>\d+)",
        re.I,
    )

    events = []
    for line in lines:
        parts = line.split(" ", 2)
        if len(parts) < 3:
            continue
        ts_raw = parts[0]
        rest = parts[2]
        try:
            ts = parse_iso(ts_raw)
            if tz and ts.tzinfo:
                ts = ts.astimezone(tz)
        except Exception:
            ts = None

        msg = re.sub(r"^\S+\[\d+\]:\s*", "", rest)
        msg = re.sub(r"^\S+:\s*", "", msg)

        if "Failed" not in msg and "Accepted" not in msg:
            continue

        kind = "FAILED" if "Failed" in msg else "ACCEPTED"
        match = fail_re.search(msg) if kind == "FAILED" else ok_re.search(msg)
        if match:
            gd = match.groupdict()
            events.append(
                {
                    "ts": ts,
                    "kind": kind,
                    "user": gd.get("user"),
                    "invalid": bool(gd.get("invalid")),
                    "ip": gd.get("ip"),
                    "port": gd.get("port"),
                    "method": gd.get("method"),
                    "raw": line,
                }
            )
        else:
            events.append(
                {
                    "ts": ts,
                    "kind": kind,
                    "user": None,
                    "invalid": None,
                    "ip": None,
                    "port": None,
                    "method": None,
                    "raw": line,
                }
            )

    return events


def build_ssh_attachment(start, end, tz):
    events = collect_ssh_logins(start, end, tz)
    lines = []
    lines.append("SSH LOGIN DETAILS")
    lines.append("-" * 18)
    lines.append(f"Host   : {os.uname().nodename}")
    lines.append(f"Period : {fmt_ts(start, tz)} to {fmt_ts(end, tz)}")
    lines.append("")

    if not events:
        lines.append("No SSH login events in this period.")
        return "pi-monitor-ssh-logins.txt", "\n".join(lines).rstrip() + "\n"

    by_day = {}
    for e in events:
        if not e.get("ts"):
            day = "(unknown date)"
        else:
            day = fmt_date(e["ts"], tz)
        by_day.setdefault(day, []).append(e)

    for day in sorted(by_day.keys(), reverse=True):
        day_items = sorted(by_day[day], key=lambda e: e["ts"] or datetime.min)
        failed = sum(1 for e in day_items if e["kind"] == "FAILED")
        accepted = sum(1 for e in day_items if e["kind"] == "ACCEPTED")
        lines.append(f"{day} (FAILED {failed}, ACCEPTED {accepted})")

        for e in day_items:
            ts = fmt_time(e["ts"], tz) if e.get("ts") else "--:--"
            user = e.get("user") or "unknown"
            invalid = e.get("invalid")
            validity = "invalid" if invalid else "valid"
            if invalid is None:
                validity = "unknown"
            ip = e.get("ip") or "unknown"
            port = e.get("port") or "unknown"
            method = e.get("method") or "unknown"
            lines.append(
                f"  {ts} | {e['kind']} | user={user} ({validity}) | ip={ip} | port={port} | method={method}"
            )
            lines.append(f"    raw: {e['raw']}")
        lines.append("")

    return "pi-monitor-ssh-logins.txt", "\n".join(lines).rstrip() + "\n"

def safe_filename(name):
    s = re.sub(r"[^A-Za-z0-9_-]+", "_", name.strip())
    s = s.strip("_")
    return s or "unknown"


def summarize_pi_monitor(start, end):
    if not os.path.exists(PI_ALERTS_LOG):
        body = "Pi monitor: alerts log not found."
        attachments = [("pi-monitor-warn-crit-none.txt", "No alerts log found.\n")]
        return body, attachments

    tz = ZoneInfo(TZ_NAME) if ZoneInfo else None
    total = 0
    counts = {"OK": 0, "WARN": 0, "CRIT": 0}
    checks = {}
    events = []
    warncrit_by_check = {}

    current_event = None

    with open(PI_ALERTS_LOG, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            m = re.match(r"\[(.+?)\]\s+(.*)$", line)
            if not m:
                if current_event is not None and line.strip():
                    current_event.setdefault("details", []).append(line)
                continue
            ts_raw = m.group(1)
            rest = m.group(2)
            try:
                ts = parse_iso(ts_raw)
            except Exception:
                continue
            if ts < start or ts > end:
                continue

            total += 1
            m2 = re.match(r"^(.*?)\s+(OK|WARN|CRIT)\s-\s*(.*)$", rest)
            if not m2:
                continue
            check = m2.group(1).strip()
            status = m2.group(2).strip()
            msg = m2.group(3).strip()

            counts[status] = counts.get(status, 0) + 1
            checks.setdefault(check, {"total": 0, "OK": 0, "WARN": 0, "CRIT": 0, "last": ts})
            checks[check]["total"] += 1
            checks[check][status] += 1
            if ts > checks[check]["last"]:
                checks[check]["last"] = ts

            current_event = {"ts": ts, "check": check, "status": status, "msg": msg, "details": []}
            events.append(current_event)

            if status in ("WARN", "CRIT"):
                warncrit_by_check.setdefault(check, []).append(current_event)

    lines = []
    lines.append("PI MONITOR WEEKLY SUMMARY")
    lines.append("-" * 28)
    lines.append(f"Host   : {os.uname().nodename}")
    lines.append(f"Period : {fmt_ts(start, tz)} to {fmt_ts(end, tz)}")
    lines.append("")
    lines.append("Totals")
    lines.append(f"  Total events : {total}")
    lines.append(f"  OK           : {counts['OK']}")
    lines.append(f"  WARN         : {counts['WARN']}")
    lines.append(f"  CRIT         : {counts['CRIT']}")
    lines.append("")

    if checks:
        top = sorted(checks.items(), key=lambda kv: kv[1]["total"], reverse=True)[:8]
        lines.append("Top checks by event count")
        for name, stats in top:
            lines.append(
                f"  {name:<16} {stats['total']:>4}  (WARN {stats['WARN']}, CRIT {stats['CRIT']})"
            )
        lines.append("")

        warncrit = [
            (name, stats)
            for name, stats in checks.items()
            if stats.get("WARN") or stats.get("CRIT")
        ]
        lines.append("Checks with WARN/CRIT")
        if warncrit:
            for name, stats in sorted(
                warncrit,
                key=lambda kv: (kv[1]["CRIT"], kv[1]["WARN"], kv[1]["total"]),
                reverse=True,
            ):
                lines.append(
                    f"  {name:<16} WARN {stats['WARN']:<3} CRIT {stats['CRIT']:<3} last {fmt_ts(stats['last'], tz)}"
                )
        else:
            lines.append("  none")
        lines.append("")

    if events:
        warncrit_events = [e for e in events if e["status"] in ("WARN", "CRIT")]
        warncrit_events.sort(key=lambda e: e["ts"], reverse=True)
        lines.append("Recent WARN/CRIT events (max 10)")
        if warncrit_events:
            for e in warncrit_events[:10]:
                lines.append(
                    f"  {fmt_ts_short(e['ts'], tz)} | {e['check']} | {e['status']}"
                )
                if e["msg"]:
                    lines.append(f"    {e['msg']}")
        else:
            lines.append("  none")
        lines.append("")

    attachment_checks = [c for c in warncrit_by_check.keys() if c != "SSH_LOGIN"]

    if attachment_checks:
        lines.append("Attachments: one file per check with WARN/CRIT + SSH login details")
        lines.append("  " + ", ".join(sorted(attachment_checks)))
    else:
        lines.append("Attachments: SSH login details (no other WARN/CRIT checks this period)")

    # Build attachments: one per check
    attachments = []
    if not attachment_checks:
        attachments.append(("pi-monitor-warn-crit-none.txt", "No WARN/CRIT events in this period.\n"))
    else:
        for check in sorted(attachment_checks):
            items = sorted(warncrit_by_check[check], key=lambda e: e["ts"], reverse=True)
            att_lines = [
                f"Check: {check}",
                f"Period: {fmt_ts(start, tz)} to {fmt_ts(end, tz)}",
                "",
                "Grouped by day (local time):",
                "",
            ]

            by_day = {}
            for e in items:
                day = fmt_date(e["ts"], tz)
                by_day.setdefault(day, []).append(e)

            for day in sorted(by_day.keys(), reverse=True):
                day_items = sorted(by_day[day], key=lambda e: e["ts"])
                warn_count = sum(1 for e in day_items if e["status"] == "WARN")
                crit_count = sum(1 for e in day_items if e["status"] == "CRIT")
                att_lines.append(f"{day} (WARN {warn_count}, CRIT {crit_count})")
                for e in day_items:
                    ts = fmt_time(e["ts"], tz)
                    msg = e["msg"] or "(no details)"
                    att_lines.append(f"  {ts} | {e['status']} | {msg}")
                    details = [ln.strip() for ln in e.get("details", []) if ln.strip()]
                    if details:
                        if check == "FS":
                            details = [ln for ln in details if not ln.lower().startswith("kernel errors") and not ln.lower().startswith("recent kernel errors")]
                        for ln in details:
                            att_lines.append(f"    {ln}")
                att_lines.append("")

            filename = f"pi-monitor-{safe_filename(check)}-warn-crit.txt"
            attachments.append((filename, "\n".join(att_lines).rstrip() + "\n"))

    ssh_name, ssh_content = build_ssh_attachment(start, end, tz)
    attachments.append((ssh_name, ssh_content))

    body = "\n".join(lines).rstrip()
    return body, attachments


def send_mail(to_addr, from_addr, subject, body, attachments, source_id):
    boundary = f"====PIMON-MIME-{int(datetime.now().timestamp())}===="
    headers = (
        f"From: {from_addr}\n"
        f"To: {to_addr}\n"
        f"Subject: {subject}\n"
        "MIME-Version: 1.0\n"
        f"Content-Type: multipart/mixed; boundary=\"{boundary}\"\n"
        "\n"
    )

    parts = []
    parts.append(f"--{boundary}\nContent-Type: text/plain; charset=UTF-8\n\n{body}\n")
    for name, content in attachments:
        parts.append(
            f"--{boundary}\n"
            f"Content-Type: text/plain; charset=UTF-8\n"
            f"Content-Disposition: attachment; filename=\"{name}\"\n\n"
            f"{content}"
        )
    parts.append(f"\n--{boundary}--\n")

    msg = headers + "".join(parts)
    proc = subprocess.run(["/usr/sbin/sendmail", "-t", "-oi"], input=msg, text=True)
    if proc.returncode == 0:
        archive_code, archive_output = archive_copy(source_id, to_addr, from_addr, subject, body, attachments)
        if archive_code != 0:
            send_failure_mail(to_addr, from_addr, subject, archive_output or "archive command failed")
            return archive_code
    return proc.returncode



def main():
    tz = ZoneInfo(TZ_NAME) if ZoneInfo else None
    now = now_local()

    p = argparse.ArgumentParser()
    p.add_argument("--start", help="Start datetime (ISO format)")
    p.add_argument("--end", help="End datetime (ISO format)")
    p.add_argument("--monthly", action="store_true", help="Send summary for previous calendar month")
    p.add_argument("--month", help="Month to summarize (YYYY-MM or 'prev')")
    args = p.parse_args()

    if args.monthly or args.month:
        if args.month and args.month not in ("prev", "previous"):
            year_s, month_s = args.month.split("-", 1)
            target = datetime(int(year_s), int(month_s), 1, tzinfo=tz)
        else:
            # previous month
            if now.month == 1:
                target = datetime(now.year - 1, 12, 1, tzinfo=tz)
            else:
                target = datetime(now.year, now.month - 1, 1, tzinfo=tz)
        start, end = month_range(target, tz)
        subject = f"Monthly Pi Monitor Summary ({start.strftime('%Y-%m')})"
    else:
        start = parse_arg_dt(args.start, tz) if args.start else None
        end = parse_arg_dt(args.end, tz) if args.end else None
        if not end:
            end = now
        if not start:
            start = end - timedelta(days=7)
        if args.start or args.end:
            subject = f"Pi Monitor Summary ({start.strftime('%Y-%m-%d')} to {end.strftime('%Y-%m-%d')})"
        else:
            subject = f"Weekly Pi Monitor Summary ({end.strftime('%Y-%m-%d')})"

    to_addr, from_addr = resolve_email()
    body, attachments = summarize_pi_monitor(start, end)

    source_id = "pi_monitor_monthly" if args.monthly or args.month else "pi_monitor_weekly"
    return send_mail(to_addr, from_addr, subject, body, attachments, source_id)


if __name__ == "__main__":
    sys.exit(main())
