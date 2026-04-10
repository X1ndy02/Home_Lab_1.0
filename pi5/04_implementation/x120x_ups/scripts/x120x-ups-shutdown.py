#!/usr/bin/env python3
import os
import shutil
import socket
import struct
import subprocess
import time
from datetime import datetime
from pathlib import Path

import gpiod

CONFIG_PATH = Path("/etc/x120x/ups-shutdown.conf")
NOTIFY_CONFIG = Path("/etc/x120x/ups-notify.conf")
F2B_JAIL_LOCAL = Path("/etc/fail2ban/jail.local")
DEFAULT_LOG_PATH = "/var/log/x120x-ups-shutdown.log"
DEFAULT_STATE_PATH = "/run/x120x-ups-shutdown.triggered"
DEFAULT_EVENT_LOG = "/var/log/x120x-ups-events.jsonl"

GPIOCHIP = "/dev/gpiochip0"
PLD_PIN = 6
BAT_ADDR = 0x36


def read_kv(path):
    data = {}
    if not path.exists():
        return data
    try:
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, val = line.split("=", 1)
            data[key.strip()] = val.strip()
    except Exception:
        return data
    return data


def parse_bool(val, default=False):
    if val is None:
        return default
    return val.strip().lower() in {"1", "true", "yes", "y", "on"}


def parse_float(val, default):
    try:
        return float(val)
    except Exception:
        return default


def parse_int(val, default):
    try:
        return int(val)
    except Exception:
        return default


def load_settings():
    cfg = read_kv(CONFIG_PATH)
    notify = read_kv(NOTIFY_CONFIG)
    f2b = read_kv(F2B_JAIL_LOCAL)

    to_addr = cfg.get("TO") or notify.get("TO") or f2b.get("destemail") or "root"
    from_addr = cfg.get("FROM") or notify.get("FROM") or f2b.get("sender") or to_addr
    subject_prefix = cfg.get("SUBJECT_PREFIX") or notify.get("SUBJECT_PREFIX") or "[UPS]"

    low_batt = parse_float(cfg.get("LOW_BATTERY_PCT"), 20.0)
    interval = parse_float(cfg.get("CHECK_INTERVAL"), 5.0)
    require_ac_loss = parse_bool(cfg.get("REQUIRE_AC_LOSS"), True)
    dry_run = parse_bool(cfg.get("DRY_RUN"), False)

    backup_cmd = cfg.get("BACKUP_CMD") or "/usr/local/sbin/ups-quick-backup.sh"
    backup_timeout = parse_int(cfg.get("BACKUP_TIMEOUT"), 300)
    backup_dir = cfg.get("BACKUP_DIR") or "/mnt/backup/UPS_shutdown_backusp"

    stop_services = cfg.get("STOP_SERVICES", "")
    stop_timeout = parse_int(cfg.get("STOP_TIMEOUT"), 25)

    log_path = cfg.get("LOG_PATH") or DEFAULT_LOG_PATH
    state_path = cfg.get("STATE_PATH") or DEFAULT_STATE_PATH
    event_log = cfg.get("EVENT_LOG_PATH") or notify.get("LOG_PATH") or DEFAULT_EVENT_LOG

    return {
        "to": to_addr,
        "from": from_addr,
        "subject_prefix": subject_prefix,
        "low_batt": low_batt,
        "interval": max(interval, 1.0),
        "require_ac_loss": require_ac_loss,
        "dry_run": dry_run,
        "backup_cmd": backup_cmd,
        "backup_timeout": backup_timeout,
        "backup_dir": backup_dir,
        "stop_services": [s for s in stop_services.split() if s.strip()],
        "stop_timeout": stop_timeout,
        "log_path": log_path,
        "state_path": state_path,
        "event_log": event_log,
    }


def log(settings, msg):
    timestamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    line = f"{timestamp} {msg}"
    print(line, flush=True)
    log_path = settings.get("log_path")
    if log_path:
        try:
            Path(log_path).parent.mkdir(parents=True, exist_ok=True)
            with open(log_path, "a", encoding="utf-8") as handle:
                handle.write(line + "\n")
        except Exception:
            pass


def find_mailer():
    for name in ("msmtp", "sendmail"):
        path = shutil.which(name)
        if path:
            return path
    return None


def send_mail(settings, subject, body):
    mailer = find_mailer()
    if not mailer:
        log(settings, "No mailer found (msmtp/sendmail).")
        return False

    timestamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    message = (
        f"From: {settings['from']}\n"
        f"To: {settings['to']}\n"
        f"Subject: {subject}\n"
        f"Date: {timestamp}\n"
        "\n"
        f"{body}\n"
    )
    result = subprocess.run([mailer, "-t"], input=message.encode("utf-8"), check=False)
    if result.returncode != 0:
        log(settings, f"Mail send failed (exit {result.returncode})")
        return False
    return True


def read_voltage(bus):
    read = bus.read_word_data(BAT_ADDR, 2)
    swapped = struct.unpack("<H", struct.pack(">H", read))[0]
    return swapped * 1.25 / 1000 / 16


def read_capacity(bus):
    read = bus.read_word_data(BAT_ADDR, 4)
    swapped = struct.unpack("<H", struct.pack(">H", read))[0]
    return swapped / 256


def read_battery(settings):
    try:
        import smbus2
    except Exception as exc:
        log(settings, f"smbus2 unavailable: {exc}")
        return None

    try:
        bus = smbus2.SMBus(1)
    except Exception as exc:
        log(settings, f"SMBus(1) open failed: {exc}")
        return None

    try:
        voltage = read_voltage(bus)
        capacity = read_capacity(bus)
    except Exception as exc:
        log(settings, f"SMBus read failed: {exc}")
        return None
    finally:
        try:
            bus.close()
        except Exception:
            pass

    return {"voltage": voltage, "capacity": capacity}


def read_ac_state_from_log(settings):
    log_path = settings.get("event_log")
    if not log_path:
        return None
    path = Path(log_path)
    if not path.exists():
        return None
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            if size == 0:
                return None
            handle.seek(-min(size, 4096), os.SEEK_END)
            lines = handle.read().splitlines()
            if not lines:
                return None
            last = lines[-1].decode("utf-8", "replace")
    except Exception:
        return None

    try:
        item = __import__("json").loads(last)
    except Exception:
        return None

    ac_ok = item.get("ac_ok")
    if ac_ok is True:
        return True
    if ac_ok is False:
        return False
    return None


def read_ac_state(settings):
    ac_ok = read_ac_state_from_log(settings)
    if ac_ok is not None:
        return ac_ok

    try:
        with gpiod.request_lines(
            GPIOCHIP,
            consumer="PLD",
            config={PLD_PIN: gpiod.LineSettings(direction=gpiod.line.Direction.INPUT)},
        ) as request:
            values = request.get_values()
            return values[0] == gpiod.line.Value.ACTIVE
    except Exception as exc:
        log(settings, f"AC state read failed: {exc}")
        return None


def run_backup(settings):
    cmd = settings.get("backup_cmd")
    if not cmd:
        log(settings, "No backup command configured.")
        return False
    log(settings, f"Running backup: {cmd}")
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            timeout=settings.get("backup_timeout", 300),
            check=False,
        )
        log(settings, f"Backup finished (exit {result.returncode})")
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        log(settings, "Backup timed out.")
        return False


def stop_services(settings):
    services = settings.get("stop_services", [])
    if not services:
        log(settings, "No services configured to stop.")
        return

    timeout = settings.get("stop_timeout", 25)
    for svc in services:
        log(settings, f"Stopping service: {svc}")
        try:
            subprocess.run(
                ["systemctl", "stop", svc],
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired:
            log(settings, f"Service stop timed out: {svc}")


def shutdown_system(settings):
    if settings.get("dry_run"):
        log(settings, "DRY_RUN enabled: skipping shutdown.")
        return

    log(settings, "Syncing disks...")
    subprocess.run(["sync"], check=False)

    log(settings, "Shutting down now.")
    subprocess.run(["systemctl", "poweroff"], check=False)


def build_email_body(settings, battery, ac_ok):
    host = socket.gethostname()
    now = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")

    lines = []
    lines.append("UPS LOW BATTERY - SHUTDOWN SEQUENCE")
    lines.append("────────────────────────────────")
    lines.append(f"Host       : {host}")
    lines.append(f"Time       : {now}")
    lines.append(f"AC power   : {'OK' if ac_ok else 'LOST' if ac_ok is False else 'UNKNOWN'}")
    if battery:
        lines.append(f"Battery    : {battery['capacity']:.1f}% ({battery['voltage']:.2f}V)")
    else:
        lines.append("Battery    : unavailable")
    lines.append(f"Threshold : {settings['low_batt']:.1f}%")
    lines.append(f"Backup dir: {settings['backup_dir']}")
    lines.append("")
    lines.append("Actions: quick backup, stop services, shutdown")
    return "\n".join(lines)


def main():
    settings = load_settings()
    log(settings, "UPS low-battery shutdown monitor started")

    state_path = Path(settings["state_path"])

    while True:
        ac_ok = read_ac_state(settings)

        if ac_ok is True:
            if state_path.exists():
                try:
                    state_path.unlink()
                except Exception:
                    pass
            time.sleep(settings["interval"])
            continue

        if settings["require_ac_loss"] and ac_ok is None:
            time.sleep(settings["interval"])
            continue

        battery = read_battery(settings)
        if not battery:
            time.sleep(settings["interval"])
            continue

        if battery["capacity"] <= settings["low_batt"]:
            if state_path.exists():
                time.sleep(settings["interval"])
                continue

            try:
                state_path.parent.mkdir(parents=True, exist_ok=True)
                state_path.write_text(f"{battery['capacity']:.1f}\n")
            except Exception:
                pass

            subject = f"{settings['subject_prefix']} LOW BATTERY {battery['capacity']:.1f}% - shutting down"
            body = build_email_body(settings, battery, ac_ok)
            send_mail(settings, subject, body)

            if settings.get("dry_run"):
                log(settings, "DRY_RUN enabled: skipping backup/stop/shutdown.")
                return 0

            run_backup(settings)
            stop_services(settings)
            shutdown_system(settings)
            return 0

        time.sleep(settings["interval"])


if __name__ == "__main__":
    raise SystemExit(main())
