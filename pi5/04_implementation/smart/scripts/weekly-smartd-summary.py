#!/usr/bin/env python3
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
CONF_PATH = "/etc/weekly-smartd-summary.conf"
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


def archive_copy(to_addr, from_addr, subject, body, attachment_name, attachment_content):
    with tempfile.TemporaryDirectory(prefix="smart-summary-") as tmpdir:
        os.chmod(tmpdir, 0o755)
        body_path = os.path.join(tmpdir, "email-body.txt")
        attachment_path = os.path.join(tmpdir, attachment_name)

        with open(body_path, "w", encoding="utf-8") as f:
            f.write(body)
            if not body.endswith("\n"):
                f.write("\n")
        with open(attachment_path, "w", encoding="utf-8") as f:
            f.write(attachment_content)
            if not attachment_content.endswith("\n"):
                f.write("\n")

        os.chmod(body_path, 0o644)
        os.chmod(attachment_path, 0o644)

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
            "smart_weekly",
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
            "--attach",
            attachment_path,
            "--push",
        ]
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
        "A git push did not complete successfully for the SMART summary email archive.\n\n"
        f"Original subject: {subject}\n"
        f"Repository: {ARCHIVE_REPO}\n\n"
        "Error:\n"
        f"{error_text}\n"
    )
    subprocess.run(["/usr/sbin/sendmail", "-t", "-oi"], input=msg, text=True)


def fmt_ts(dt, tz):
    if tz and dt.tzinfo:
        dt = dt.astimezone(tz)
    return dt.strftime("%Y-%m-%d %H:%M %Z")


def simplify_line(line):
    line = re.sub(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \S+ \S+ ", "", line)
    line = re.sub(r"smartd\[\d+\]:\s*", "", line)
    return line.strip()


def smartd_summary(start, end):
    tz = ZoneInfo(TZ_NAME) if ZoneInfo else None
    since = start.strftime("%Y-%m-%d %H:%M:%S")
    until = end.strftime("%Y-%m-%d %H:%M:%S")
    cmd = [
        "journalctl",
        "-u",
        "smartd",
        "--since",
        since,
        "--until",
        until,
        "--no-pager",
        "--output",
        "short-iso",
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out = res.stdout.strip()
    lines = [ln for ln in out.splitlines() if ln.strip()]

    warn_re = re.compile(r"fail|error|crit|temperature|reallocated|uncorrect|offline|corrupt", re.I)
    total = len(lines)
    warn = 0
    devices = set()
    parsed = []

    for ln in lines:
        m = re.match(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(\S+)\s+(.*)$", ln)
        if m:
            ts_raw = m.group(1)
            try:
                ts = datetime.strptime(ts_raw, "%Y-%m-%d %H:%M:%S")
                if tz:
                    ts = ts.replace(tzinfo=tz)
            except Exception:
                ts = None
        else:
            ts = None

        sev = "WARN" if warn_re.search(ln) else "INFO"
        if sev == "WARN":
            warn += 1

        devm = re.findall(r"/dev/\w+", ln)
        for d in devm:
            devices.add(d)

        parsed.append({"ts": ts, "sev": sev, "raw": ln})

    parsed_warn = [p for p in parsed if p["sev"] == "WARN"]
    parsed_warn.sort(key=lambda p: p["ts"] or datetime.min, reverse=True)
    parsed_all = sorted(parsed, key=lambda p: p["ts"] or datetime.min, reverse=True)

    out_lines = []
    out_lines.append("SMART DISK WEEKLY SUMMARY")
    out_lines.append("-" * 27)
    out_lines.append(f"Host   : {os.uname().nodename}")
    out_lines.append(f"Period : {fmt_ts(start, tz)} to {fmt_ts(end, tz)}")
    out_lines.append("")
    out_lines.append("Totals")
    out_lines.append(f"  Log lines       : {total}")
    out_lines.append(f"  Warnings/errors : {warn}")
    if devices:
        out_lines.append(f"  Devices seen    : {', '.join(sorted(devices))}")
    out_lines.append("")

    out_lines.append("Warnings/errors (most recent first, max 10)")
    if parsed_warn:
        for p in parsed_warn[:10]:
            ts = fmt_ts(p["ts"], tz) if p["ts"] else "(time unknown)"
            out_lines.append(f"  {ts}")
            out_lines.append(f"    {simplify_line(p['raw'])}")
    else:
        out_lines.append("  none")
    out_lines.append("")

    out_lines.append("Recent smartd activity (max 5)")
    if parsed_all:
        for p in parsed_all[:5]:
            ts = fmt_ts(p["ts"], tz) if p["ts"] else "(time unknown)"
            out_lines.append(f"  {ts}")
            out_lines.append(f"    {simplify_line(p['raw'])}")
    else:
        out_lines.append("  none")

    out_lines.append("")
    out_lines.append("Full log lines are attached.")

    if lines:
        attachment = "\n".join(lines) + "\n"
    else:
        attachment = "No smartd log lines in this period.\n"
    return "\n".join(out_lines).rstrip(), attachment


def send_mail(to_addr, from_addr, subject, body, attachment_name, attachment_content):
    boundary = f"====SMARTD-MIME-{int(datetime.now().timestamp())}===="
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
    parts.append(
        f"--{boundary}\n"
        f"Content-Type: text/plain; charset=UTF-8\n"
        f"Content-Disposition: attachment; filename=\"{attachment_name}\"\n\n"
        f"{attachment_content}"
    )
    parts.append(f"\n--{boundary}--\n")

    msg = headers + "".join(parts)
    proc = subprocess.run(["/usr/sbin/sendmail", "-t", "-oi"], input=msg, text=True)
    if proc.returncode == 0:
        archive_code, archive_output = archive_copy(
            to_addr,
            from_addr,
            subject,
            body,
            attachment_name,
            attachment_content,
        )
        if archive_code != 0:
            send_failure_mail(to_addr, from_addr, subject, archive_output or "archive command failed")
            return archive_code
    return proc.returncode


def main():
    now = now_local()
    start = now - timedelta(days=7)
    end = now

    to_addr, from_addr = resolve_email()
    subject = f"Weekly SMART Summary ({now.strftime('%Y-%m-%d')})"
    body, attachment = smartd_summary(start, end)
    attach_name = f"smartd-log-{now.strftime('%Y-%m-%d')}.txt"

    return send_mail(to_addr, from_addr, subject, body, attach_name, attachment)


if __name__ == "__main__":
    sys.exit(main())
