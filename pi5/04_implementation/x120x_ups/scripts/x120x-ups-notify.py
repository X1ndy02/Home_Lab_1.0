#!/usr/bin/env python3
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import gpiod

CONFIG_PATH = Path("/etc/x120x/ups-notify.conf")
F2B_JAIL_LOCAL = Path("/etc/fail2ban/jail.local")
GPIOCHIP = "/dev/gpiochip0"
PLD_PIN = 6
BAT_ADDR = 0x36
DEFAULT_LOG_PATH = "/var/log/x120x-ups-events.jsonl"


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
    except Exception as exc:
        log(f"Config read failed: {path}: {exc}")
    return data


def parse_bool(val, default=False):
    if val is None:
        return default
    return val.strip().lower() in {"1", "true", "yes", "y", "on"}


def log(msg):
    print(msg, flush=True)


def find_mailer():
    for name in ("msmtp", "sendmail"):
        path = shutil.which(name)
        if path:
            return path
    return None


def load_settings():
    cfg = read_kv(CONFIG_PATH)
    f2b = read_kv(F2B_JAIL_LOCAL)

    to_addr = cfg.get("TO") or f2b.get("destemail") or "root"
    from_addr = cfg.get("FROM") or f2b.get("sender") or to_addr
    subject_prefix = cfg.get("SUBJECT_PREFIX") or "[UPS]"
    notify_restore = parse_bool(cfg.get("NOTIFY_ON_RESTORE"), default=False)
    log_path = cfg.get("LOG_PATH") or DEFAULT_LOG_PATH
    if log_path == "":
        log_path = None

    try:
        interval = float(cfg.get("CHECK_INTERVAL", "2"))
    except ValueError:
        interval = 2.0

    return {
        "to": to_addr,
        "from": from_addr,
        "subject_prefix": subject_prefix,
        "notify_restore": notify_restore,
        "interval": max(interval, 0.5),
        "log_path": log_path,
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
    if result.returncode != 0:
        log(f"Mail send failed (exit {result.returncode})")
        return False
    return True


def format_bytes(num):
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if num < 1024 or unit == "TiB":
            return f"{num:.1f} {unit}"
        num /= 1024
    return f"{num:.1f} TiB"


def format_uptime(seconds):
    minutes, sec = divmod(int(seconds), 60)
    hours, minutes = divmod(minutes, 60)
    days, hours = divmod(hours, 24)
    if days:
        return f"{days}d {hours:02d}:{minutes:02d}:{sec:02d}"
    return f"{hours:02d}:{minutes:02d}:{sec:02d}"


def format_uptime_short(seconds):
    minutes, sec = divmod(int(seconds), 60)
    hours, minutes = divmod(minutes, 60)
    days, hours = divmod(hours, 24)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def get_uptime_seconds():
    try:
        uptime = Path("/proc/uptime").read_text().split()[0]
        return float(uptime)
    except Exception:
        return None


def format_gib(num_bytes):
    return f"{num_bytes / (1024**3):.1f} GiB"


def battery_health_label(pct):
    if pct is None:
        return "unknown"
    if pct >= 50:
        return "healthy"
    if pct >= 20:
        return "ok"
    if pct >= 10:
        return "low"
    return "critical"


def cpu_temp_status(temp):
    if temp is None:
        return "unknown"
    if temp < 70:
        return "normal"
    if temp < 80:
        return "warm"
    return "hot"


def build_power_event_body(ac_ok, event_title, note=None):
    now = datetime.now().astimezone()
    host = socket.gethostname()

    battery = read_battery()
    battery_line = "Battery  : unavailable"
    fuel_gauge = "Fuel gauge : unknown"
    if battery and "error" in battery:
        battery_line = f"Battery  : unavailable ({battery['error']})"
        fuel_gauge = "Fuel gauge : ERROR (I2C 0x36)"
    elif battery:
        pct = battery.get("capacity")
        health = battery_health_label(pct)
        battery_line = f"Battery  : {pct:.0f}% ({health})"
        fuel_gauge = "Fuel gauge : OK (I2C 0x36)"

    state = "UNKNOWN"
    if ac_ok is True:
        state = "On AC power"
    elif ac_ok is False:
        state = "Running on battery"

    lines = []
    lines.append(f"POWER EVENT · {event_title}")
    lines.append("─────────────────────")
    lines.append(f"Host     : {host}")
    lines.append(f"Time     : {now.strftime('%a %b %d, %H:%M %Z')}")
    lines.append(f"State    : {state}")
    lines.append(battery_line)
    lines.append("")
    lines.append("SYSTEM STATUS")

    uptime_sec = get_uptime_seconds()
    if uptime_sec is not None:
        lines.append(f"• Uptime     : {format_uptime_short(uptime_sec)} (no reboot)")

    load = get_loadavg()
    if load:
        lines.append(f"• Load       : {load}")

    temp = get_cpu_temp()
    if temp is not None:
        lines.append(f"• CPU temp   : {temp:.1f}°C ({cpu_temp_status(temp)})")

    mem = get_meminfo()
    if mem:
        lines.append(f"• Memory     : {format_gib(mem['used'])} / {format_gib(mem['total'])}")

    disk = get_disk_usage()
    if disk:
        lines.append(f"• Disk (/ )  : {format_gib(disk['used'])} / {format_gib(disk['total'])}")

    lines.append("")
    lines.append("HARDWARE")

    hw_model = get_hw_model()
    if hw_model:
        lines.append(f"• Device     : {hw_model}")

    os_release = read_os_release()
    if os_release:
        lines.append(f"• OS         : {os_release}")

    kernel = os.uname().release
    lines.append(f"• Kernel     : {kernel}")
    lines.append(f"• {fuel_gauge}")

    if note:
        lines.append("")
        lines.append(f"Note     : {note}")

    return "\n".join(lines)


def read_os_release():
    data = read_kv(Path("/etc/os-release"))
    return data.get("PRETTY_NAME") or data.get("NAME")


def get_uptime():
    try:
        uptime = Path("/proc/uptime").read_text().split()[0]
        return format_uptime(float(uptime))
    except Exception:
        return None


def get_loadavg():
    try:
        parts = Path("/proc/loadavg").read_text().split()
        return " ".join(parts[:3])
    except Exception:
        return None


def get_meminfo():
    values = {}
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if ":" not in line:
                continue
            key, val = line.split(":", 1)
            values[key.strip()] = int(val.strip().split()[0]) * 1024
    except Exception:
        return None
    total = values.get("MemTotal")
    avail = values.get("MemAvailable")
    if total is None or avail is None:
        return None
    used = total - avail
    return {
        "total": total,
        "used": used,
        "avail": avail,
    }


def get_disk_usage():
    try:
        total, used, free = shutil.disk_usage("/")
        return {
            "total": total,
            "used": used,
            "free": free,
        }
    except Exception:
        return None


def get_cpu_temp():
    temp_path = Path("/sys/class/thermal/thermal_zone0/temp")
    if not temp_path.exists():
        return None
    try:
        raw = temp_path.read_text().strip()
        return int(raw) / 1000.0
    except Exception:
        return None


def get_hw_model():
    model_path = Path("/proc/device-tree/model")
    if model_path.exists():
        try:
            raw = model_path.read_bytes().split(b"\x00", 1)[0]
            return raw.decode("ascii", "ignore").strip()
        except Exception:
            pass
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        try:
            for line in cpuinfo.read_text().splitlines():
                if line.lower().startswith("model"):
                    return line.split(":", 1)[1].strip()
        except Exception:
            pass
    return None


def get_ip_addrs():
    cmds = [
        ["hostname", "-I"],
        ["ip", "-o", "-4", "addr", "show", "scope", "global"],
    ]
    for cmd in cmds:
        try:
            out = subprocess.check_output(cmd, text=True).strip()
        except Exception:
            continue
        if not out:
            continue
        if cmd[0] == "hostname":
            return out.split()
        ips = []
        for line in out.splitlines():
            parts = line.split()
            if "inet" in parts:
                ip = parts[parts.index("inet") + 1].split("/")[0]
                ips.append(ip)
        if ips:
            return ips
    return []


def read_voltage(bus):
    read = bus.read_word_data(BAT_ADDR, 2)
    swapped = struct.unpack("<H", struct.pack(">H", read))[0]
    return swapped * 1.25 / 1000 / 16


def read_capacity(bus):
    read = bus.read_word_data(BAT_ADDR, 4)
    swapped = struct.unpack("<H", struct.pack(">H", read))[0]
    return swapped / 256


def read_battery():
    try:
        import smbus2
    except Exception as exc:
        return {"error": f"smbus2 unavailable: {exc}"}

    try:
        bus = smbus2.SMBus(1)
    except Exception as exc:
        return {"error": f"SMBus(1) open failed: {exc}"}

    try:
        voltage = read_voltage(bus)
        capacity = read_capacity(bus)
    except Exception as exc:
        return {"error": f"SMBus read failed: {exc}"}
    finally:
        try:
            bus.close()
        except Exception:
            pass

    return {
        "voltage": voltage,
        "capacity": capacity,
    }


def read_ac_state():
    try:
        with gpiod.request_lines(
            GPIOCHIP,
            consumer="PLD",
            config={
                PLD_PIN: gpiod.LineSettings(direction=gpiod.line.Direction.INPUT)
            },
        ) as request:
            values = request.get_values()
            return values[0] == gpiod.line.Value.ACTIVE
    except Exception as exc:
        log(f"AC state read failed: {exc}")
        return None


def log_event(settings, event, ac_ok, battery=None, note=None):
    log_path = settings.get("log_path")
    if not log_path:
        return

    now = datetime.now().astimezone()
    payload = {
        "ts": now.strftime("%Y-%m-%d %H:%M:%S %z"),
        "epoch": int(now.timestamp()),
        "event": event,
        "ac_ok": ac_ok,
        "host": socket.gethostname(),
    }

    if battery is None:
        battery = read_battery()

    if battery and "error" in battery:
        payload["battery_error"] = battery["error"]
    elif battery:
        payload["battery_voltage"] = round(battery["voltage"], 3)
        payload["battery_pct"] = round(battery["capacity"], 1)

    if note:
        payload["note"] = note

    try:
        Path(log_path).parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=True, separators=(",", ":"))
            handle.write("\n")
    except Exception as exc:
        log(f"Event log write failed: {exc}")


def gather_details(ac_ok, event_label=None, note=None):
    event = event_label or ("AC RESTORED" if ac_ok else "AC LOST")
    return build_power_event_body(ac_ok, event, note=note)


def send_snapshot(settings, mailer):
    host = socket.gethostname()
    ac_ok = read_ac_state()
    subject = f"{settings['subject_prefix']} Status snapshot on {host}"
    body = build_power_event_body(ac_ok, "STATUS SNAPSHOT", note="Requested manually")
    return send_mail(mailer, settings["to"], settings["from"], subject, body)


def main():
    settings = load_settings()
    mailer = find_mailer()
    if not mailer:
        log("No mailer found (msmtp/sendmail). Install msmtp or sendmail.")
        return 1

    if "--test" in sys.argv or "--snapshot" in sys.argv:
        return 0 if send_snapshot(settings, mailer) else 1

    log("UPS power monitor started")

    last_state = None

    with gpiod.request_lines(
        GPIOCHIP,
        consumer="PLD",
        config={
            PLD_PIN: gpiod.LineSettings(direction=gpiod.line.Direction.INPUT)
        },
    ) as request:
        while True:
            values = request.get_values()
            ac_ok = values[0] == gpiod.line.Value.ACTIVE

            if last_state is None:
                battery = read_battery()
                log_event(settings, "START", ac_ok, battery=battery)
                if not ac_ok:
                    log_event(settings, "AC_LOST", ac_ok, battery=battery)
                    subject = f"{settings['subject_prefix']} POWER EVENT · AC LOST"
                    body = build_power_event_body(ac_ok, "AC LOST")
                    send_mail(mailer, settings["to"], settings["from"], subject, body)
                last_state = ac_ok
            elif ac_ok != last_state:
                battery = read_battery()
                if not ac_ok:
                    log_event(settings, "AC_LOST", ac_ok, battery=battery)
                    subject = f"{settings['subject_prefix']} POWER EVENT · AC LOST"
                    body = build_power_event_body(ac_ok, "AC LOST")
                    send_mail(mailer, settings["to"], settings["from"], subject, body)
                else:
                    log_event(settings, "AC_RESTORED", ac_ok, battery=battery)
                    if settings["notify_restore"]:
                        subject = f"{settings['subject_prefix']} POWER EVENT · AC RESTORED"
                        body = build_power_event_body(ac_ok, "AC RESTORED")
                        send_mail(mailer, settings["to"], settings["from"], subject, body)
                last_state = ac_ok

            time.sleep(settings["interval"])


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        log("UPS power monitor stopped")
