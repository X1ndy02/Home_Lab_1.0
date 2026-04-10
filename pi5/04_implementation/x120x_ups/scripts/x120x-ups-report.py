#!/usr/bin/env python3
import json
import shutil
import socket
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

CONFIG_PATH = Path("/etc/x120x/ups-notify.conf")
DEFAULT_LOG_PATH = "/var/log/x120x-ups-events.jsonl"


def read_kv(path):
    data = {}
    if not path.exists():
        return data
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        data[key.strip()] = val.strip()
    return data


def find_mailer():
    for name in ("msmtp", "sendmail"):
        path = shutil.which(name)
        if path:
            return path
    return None


def load_settings():
    cfg = read_kv(CONFIG_PATH)
    to_addr = cfg.get("TO") or "root"
    from_addr = cfg.get("FROM") or to_addr
    subject_prefix = cfg.get("SUBJECT_PREFIX") or "[UPS]"
    log_path = cfg.get("LOG_PATH") or DEFAULT_LOG_PATH
    list_limit = cfg.get("REPORT_LIST_LIMIT")
    try:
        list_limit = int(list_limit) if list_limit else 50
    except ValueError:
        list_limit = 50

    return {
        "to": to_addr,
        "from": from_addr,
        "subject_prefix": subject_prefix,
        "log_path": log_path,
        "list_limit": max(list_limit, 0),
    }


def send_mail(mailer, to_addr, from_addr, subject, body):
    timestamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    message = (
        f"From: {from_addr}\n"
        f"To: {to_addr}\n"
        f"Subject: {subject}\n"
        f"Date: {timestamp}\n"
        "\n"
        f"{body}\n"
    )
    result = subprocess.run(
        [mailer, "-t"],
        input=message.encode("utf-8"),
        check=False,
    )
    return result.returncode == 0


def format_duration(seconds):
    seconds = int(seconds)
    minutes, sec = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    days, hours = divmod(hours, 24)
    if days:
        return f"{days}d {hours:02d}:{minutes:02d}:{sec:02d}"
    return f"{hours:02d}:{minutes:02d}:{sec:02d}"


def month_range(now):
    start_current = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    prev_end = start_current
    prev_last_day = start_current - timedelta(days=1)
    prev_start = prev_last_day.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    return prev_start, prev_end


def read_events(path):
    events = []
    if not path.exists():
        return events
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except Exception:
            continue
        event = item.get("event")
        if event not in {"AC_LOST", "AC_RESTORED"}:
            continue
        epoch = item.get("epoch")
        ac_ok = item.get("ac_ok")
        if epoch is None or ac_ok is None:
            continue
        try:
            epoch = int(epoch)
        except ValueError:
            continue
        events.append((epoch, bool(ac_ok), event))
    events.sort(key=lambda x: x[0])
    return events


def compute_sessions(events, start_epoch, end_epoch):
    last_state = None
    for epoch, ac_ok, _event in events:
        if epoch >= start_epoch:
            break
        last_state = ac_ok

    sessions = []
    battery_start = None
    if last_state is False:
        battery_start = start_epoch

    for epoch, ac_ok, event in events:
        if epoch < start_epoch:
            continue
        if epoch >= end_epoch:
            break
        if event == "AC_LOST":
            if battery_start is None:
                battery_start = epoch
        elif event == "AC_RESTORED":
            if battery_start is not None:
                sessions.append((battery_start, epoch))
                battery_start = None

    if battery_start is not None:
        sessions.append((battery_start, end_epoch))

    return sessions, last_state


def format_events(sessions, tzinfo, limit):
    lines = []
    if not sessions:
        return lines
    count = 0
    for start_epoch, end_epoch in sessions:
        count += 1
        if limit and count > limit:
            lines.append("(truncated)")
            break
        start_dt = datetime.fromtimestamp(start_epoch, tz=tzinfo)
        end_dt = datetime.fromtimestamp(end_epoch, tz=tzinfo)
        duration = format_duration(end_epoch - start_epoch)
        lines.append(
            f"{count}. {start_dt.strftime('%Y-%m-%d %H:%M:%S %z')} -> {end_dt.strftime('%Y-%m-%d %H:%M:%S %z')} ({duration})"
        )
    return lines


def build_report(events, start_dt, end_dt, list_limit):
    start_epoch = int(start_dt.timestamp())
    end_epoch = int(end_dt.timestamp())
    sessions, last_state = compute_sessions(events, start_epoch, end_epoch)

    total = sum(end - start for start, end in sessions)
    count = len(sessions)
    longest = max((end - start for start, end in sessions), default=0)
    average = total / count if count else 0

    lines = []
    lines.append("Monthly UPS battery report")
    lines.append(f"Host: {socket.gethostname()}")
    lines.append(
        f"Period: {start_dt.strftime('%Y-%m-%d %H:%M:%S %z')} -> {end_dt.strftime('%Y-%m-%d %H:%M:%S %z')}")
    lines.append(f"Battery events: {count}")
    lines.append(f"Total time on battery: {format_duration(total)}")
    lines.append(f"Longest event: {format_duration(longest)}")
    lines.append(f"Average duration: {format_duration(average)}")

    if last_state is False:
        lines.append("Note: AC was already lost at the start of this period.")

    if sessions:
        lines.append("")
        lines.append("Events:")
        lines.extend(format_events(sessions, start_dt.tzinfo, list_limit))
    else:
        lines.append("")
        lines.append("No battery events recorded in this period.")

    return "\n".join(lines)


def main():
    settings = load_settings()
    mailer = find_mailer()
    if not mailer:
        return 1

    log_path = Path(settings["log_path"])
    now = datetime.now().astimezone()
    start_dt, end_dt = month_range(now)

    events = read_events(log_path)

    if not log_path.exists():
        body = (
            "Monthly UPS battery report\n"
            f"Host: {socket.gethostname()}\n"
            f"Period: {start_dt.strftime('%Y-%m-%d %H:%M:%S %z')} -> {end_dt.strftime('%Y-%m-%d %H:%M:%S %z')}\n\n"
            f"No log data found at {log_path}.\n"
        )
    else:
        body = build_report(events, start_dt, end_dt, settings["list_limit"])

    subject = (
        f"{settings['subject_prefix']} Monthly battery report for {socket.gethostname()}"
        f" ({start_dt.strftime('%B %Y')})"
    )

    return 0 if send_mail(mailer, settings["to"], settings["from"], subject, body) else 1


if __name__ == "__main__":
    raise SystemExit(main())
