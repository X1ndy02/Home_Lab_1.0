#!/usr/bin/env python3
import argparse
import re
import shutil
import subprocess
import time
import socket

import psutil
import serial


def run_cmd(cmd):
    try:
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL, timeout=2.0)
        return out.strip()
    except Exception:
        return ""


def get_cpu_temp():
    out = run_cmd(["vcgencmd", "measure_temp"])
    m = re.search(r"temp=([0-9.]+)", out)
    if m:
        return m.group(1)

    try:
        temps = psutil.sensors_temperatures()
        for entries in temps.values():
            for entry in entries:
                if entry.current is not None:
                    return f"{entry.current:.1f}"
    except Exception:
        pass
    return "--"


def get_throttle_current():
    out = run_cmd(["vcgencmd", "get_throttled"])
    m = re.search(r"0x([0-9a-fA-F]+)", out)
    if not m:
        return "--"
    value = int(m.group(1), 16)
    # Bit 2: currently throttled
    return "1" if (value & 0x4) else "0"


def get_ping_ms(host):
    out = run_cmd(["ping", "-n", "-c", "1", "-W", "1", host])
    m = re.search(r"time=([0-9.]+)", out)
    if not m:
        return "--"
    return str(int(round(float(m.group(1)))))


def get_ups_percent():
    if shutil.which("upsc"):
        listed = run_cmd(["upsc", "-l"])
        if listed:
            ups_name = listed.splitlines()[0].strip()
            if ups_name:
                details = run_cmd(["upsc", ups_name])
                for line in details.splitlines():
                    if line.lower().startswith("battery.charge:"):
                        value = line.split(":", 1)[1].strip()
                        return value.split(".")[0]

    if shutil.which("apcaccess"):
        details = run_cmd(["apcaccess", "status"])
        for line in details.splitlines():
            if line.startswith("BCHARGE"):
                value = line.split(":", 1)[1].strip().split()[0]
                return value.split(".")[0]

    # Geekworm X1201 fuel gauge (MAX1704x/17048 class) at I2C 0x36.
    # SOC register 0x04 returns percent in 1/256 units.
    try:
        try:
            from smbus import SMBus
        except Exception:
            from smbus2 import SMBus  # fallback
        bus = SMBus(1)
        raw = bus.read_word_data(0x36, 0x04)
        bus.close()
        raw = ((raw & 0xFF) << 8) | (raw >> 8)
        soc = raw / 256.0
        if 0.0 <= soc <= 100.0:
            return f"{soc:.1f}"
    except Exception:
        pass

    return "--"


def get_ip_fields():
    stats = psutil.net_if_stats()
    addrs = psutil.net_if_addrs()
    items = []
    for iface, addr_list in addrs.items():
        if iface == "lo":
            continue
        if iface.startswith(("br-", "docker", "veth", "vet", "lo")):
            continue
        st = stats.get(iface)
        if st and not st.isup:
            continue
        for addr in addr_list:
            if addr.family == socket.AF_INET:
                ip = addr.address
                if ip.startswith("127."):
                    continue
                items.append((iface, ip))

    def key(it):
        iface = it[0]
        if iface == "eth0":
            return (0, iface)
        if iface == "wlan0":
            return (1, iface)
        if iface.startswith("zty"):
            return (2, iface)
        if iface.startswith("en"):
            return (3, iface)
        if iface.startswith("wl"):
            return (4, iface)
        return (9, iface)

    items = sorted(items, key=key)
    seen = set()
    out = []
    for iface, ip in items:
        if ip in seen:
            continue
        seen.add(ip)
        out.append((iface, ip))
        if len(out) >= 3:
            break

    if not out:
        return ("--", "", "")

    def tag(iface):
        if iface.startswith("zty"):
            return "ZT"
        if iface.startswith("eth"):
            return "E"
        if iface.startswith("wl"):
            return "W"
        if iface.startswith("en"):
            return "E"
        return iface[:3].upper()

    ip1 = f"{tag(out[0][0])}:{out[0][1]}"
    ip2 = f"{tag(out[1][0])}:{out[1][1]}" if len(out) > 1 else ""
    ip3 = f"{tag(out[2][0])}:{out[2][1]}" if len(out) > 2 else ""
    return (ip1, ip2, ip3)


def is_daytime(start_hhmm="06:00", end_hhmm="21:00"):
    try:
        sh, sm = [int(x) for x in start_hhmm.split(":")]
        eh, em = [int(x) for x in end_hhmm.split(":")]
        now = time.localtime()
        cur = now.tm_hour * 60 + now.tm_min
        start = sh * 60 + sm
        end = eh * 60 + em
        if start <= end:
            return start <= cur < end
        return cur >= start or cur < end
    except Exception:
        return True


def top_services(limit=7):
    buckets = {}
    for proc in psutil.process_iter(["name"]):
        try:
            cpu = proc.cpu_percent(None)
            if cpu <= 0:
                continue
            name = (proc.info.get("name") or "unknown").strip()[:12]
            buckets[name] = buckets.get(name, 0.0) + cpu
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    ranked = sorted(buckets.items(), key=lambda kv: kv[1], reverse=True)[:limit]
    while len(ranked) < limit:
        ranked.append(("-", 0.0))
    return [(name, round(cpu, 1)) for name, cpu in ranked]


def make_payload(ping_host):
    host = socket.gethostname()
    cpu = int(round(psutil.cpu_percent(interval=None)))
    ram = int(round(psutil.virtual_memory().percent))
    tm = time.strftime("%H:%M:%S", time.localtime())
    dt = time.strftime("%Y-%m-%d", time.localtime())
    temp = get_cpu_temp()
    thr = get_throttle_current()
    ping = get_ping_ms(ping_host)
    ups = get_ups_percent()
    ip1, ip2, ip3 = get_ip_fields()

    # Day/Night text color (RGB565). Day: 06:00–21:00, Night: 21:00–06:00.
    # Day color #9 = 0xFFFF (white). Night color from shade #6 = 0x04C0.
    day_color = 0xFFFF
    night_color = 0x04C0
    col = day_color if is_daytime() else night_color

    services = top_services(7)
    fields = [
        f"host={host}",
        f"cpu={cpu}",
        f"ram={ram}",
        f"tm={tm}",
        f"dt={dt}",
        f"ups={ups}",
        f"ping={ping}",
        f"temp={temp}",
        f"thr={thr}",
        f"col={col}",
        f"s1={services[0][0]}:{services[0][1]:.1f}",
        f"s2={services[1][0]}:{services[1][1]:.1f}",
        f"s3={services[2][0]}:{services[2][1]:.1f}",
        f"s4={services[3][0]}:{services[3][1]:.1f}",
        f"s5={services[4][0]}:{services[4][1]:.1f}",
        f"s6={services[5][0]}:{services[5][1]:.1f}",
        f"s7={services[6][0]}:{services[6][1]:.1f}",
        f"ip1={ip1}",
        f"ip2={ip2}",
        f"ip3={ip3}",
    ]
    return ";".join(fields)


def main():
    parser = argparse.ArgumentParser(description="Send Pi stats to RP2350 LCD over USB CDC serial.")
    parser.add_argument("--port", default="/dev/ttyACM0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--ping-host", default="1.1.1.1")
    args = parser.parse_args()

    # Prime per-process CPU counters so next sample is meaningful.
    for proc in psutil.process_iter(["name"]):
        try:
            proc.cpu_percent(None)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    psutil.cpu_percent(interval=None)
    time.sleep(1.0)

    with serial.Serial(args.port, args.baud, timeout=1, write_timeout=1) as ser:
        time.sleep(1.0)
        while True:
            payload = make_payload(args.ping_host)
            ser.write((payload + "\n").encode("utf-8"))
            ser.flush()
            print(payload, flush=True)
            time.sleep(args.interval)


if __name__ == "__main__":
    main()
