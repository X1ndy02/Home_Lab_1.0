#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from datetime import datetime
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

CONFIG_PATH = "/etc/partition-health-check.conf"
TZ_NAME = "Australia/Sydney"


def load_config(path):
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


def run(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def lsblk_partitions():
    res = run(["lsblk", "-J", "-o", "NAME,TYPE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS"])
    if res.returncode != 0:
        raise RuntimeError(f"lsblk failed: {res.stdout.strip()}")
    data = json.loads(res.stdout)

    parts = []

    def walk(node):
        if node.get("type") == "part":
            parts.append(node)
        for ch in node.get("children") or []:
            walk(ch)

    for n in data.get("blockdevices", []):
        walk(n)
    return parts


def check_vfat(dev):
    res = run(["fsck.vfat", "-n", dev])
    out = res.stdout
    dirty = bool(re.search(r"Dirty bit is set", out, re.IGNORECASE))
    bootdiff = "boot sector and its backup" in out
    return {
        "dirty": dirty,
        "bootdiff": bootdiff,
        "raw": out.strip(),
    }


def check_ext4(dev):
    res = run(["tune2fs", "-l", dev])
    if res.returncode != 0:
        return {"state": None, "raw": res.stdout.strip()}
    state = None
    for line in res.stdout.splitlines():
        if line.lower().startswith("filesystem state"):
            state = line.split(":", 1)[1].strip()
            break
    return {"state": state, "raw": res.stdout.strip()}


def now_local():
    if ZoneInfo:
        return datetime.now(ZoneInfo(TZ_NAME))
    return datetime.now()


def send_smtp(cfg, subject, body):
    import smtplib
    from email.message import EmailMessage

    host = cfg.get("SMTP_HOST")
    port = int(cfg.get("SMTP_PORT", "25"))
    user = cfg.get("SMTP_USER")
    password = cfg.get("SMTP_PASS")
    sender = cfg.get("SMTP_FROM")
    to = cfg.get("SMTP_TO")
    starttls = cfg.get("SMTP_STARTTLS", "false").lower() == "true"
    use_tls = cfg.get("SMTP_TLS", "false").lower() == "true"

    missing = [k for k in ("SMTP_HOST", "SMTP_FROM", "SMTP_TO") if not cfg.get(k)]
    if missing:
        raise RuntimeError(f"Missing SMTP config keys: {', '.join(missing)}")

    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)

    if use_tls:
        server = smtplib.SMTP_SSL(host, port, timeout=30)
    else:
        server = smtplib.SMTP(host, port, timeout=30)
    try:
        server.ehlo()
        if starttls:
            server.starttls()
            server.ehlo()
        if user and password:
            server.login(user, password)
        server.send_message(msg)
    finally:
        try:
            server.quit()
        except Exception:
            pass


def main():
    cfg = load_config(CONFIG_PATH)
    if "--test" in sys.argv:
        ts = now_local().strftime("%Y-%m-%d %H:%M:%S %Z")
        subject = f"TEST: Dirty/unclean filesystem detected ({ts})"
        body_lines = [
            f"Host: {os.uname().nodename}",
            f"Time: {ts}",
            "",
            "Detected issues:",
            "- /dev/sdz1 (ext4) mount=/ issue=state:not_clean",
            "  Details:",
            "    Filesystem state: not clean",
            "",
            "Notes:",
            "- /dev/sdz1 (ext4) note=simulated-test",
            "",
            "This is a TEST email triggered by --test.",
        ]
        body = "\n".join(body_lines)
        send_smtp(cfg, subject, body)
        return 0

    parts = lsblk_partitions()
    issues = []
    notes = []

    for p in parts:
        name = p.get("name")
        fstype = (p.get("fstype") or "").lower()
        dev = f"/dev/{name}"
        mounts = p.get("mountpoints") or []
        mnt = ",".join([m for m in mounts if m]) or "-"

        if fstype in ("vfat", "fat", "fat32"):
            r = check_vfat(dev)
            if r["dirty"]:
                issues.append((dev, fstype, mnt, "dirty-bit", r["raw"]))
            if r["bootdiff"] and not r["dirty"]:
                notes.append((dev, fstype, mnt, "boot-sector-backup-diff", r["raw"]))
        elif fstype in ("ext4", "ext3", "ext2"):
            r = check_ext4(dev)
            state = r.get("state")
            if state and state.lower() not in ("clean",):
                issues.append((dev, fstype, mnt, f"state:{state}", r["raw"]))
        elif fstype:
            notes.append((dev, fstype, mnt, "unsupported-fs", "No dirty-bit check for this filesystem."))

    if not issues:
        return 0

    ts = now_local().strftime("%Y-%m-%d %H:%M:%S %Z")
    subject = f"ALERT: Dirty/unclean filesystem detected ({ts})"

    expl = (
        "What is the dirty bit?\n"
        "- On FAT/vfat filesystems, a 'dirty bit' flag is set when the filesystem was not cleanly unmounted.\n"
        "- It is normally cleared on a clean unmount. If it stays set, a filesystem check is recommended.\n"
        "- Causes include sudden power loss, hard resets, or removing media while mounted.\n\n"
    )

    body_lines = [
        f"Host: {os.uname().nodename}",
        f"Time: {ts}",
        "",
        "Detected issues:",
    ]
    for dev, fs, mnt, reason, raw in issues:
        body_lines.append(f"- {dev} ({fs}) mount={mnt} issue={reason}")
        if raw:
            body_lines.append("  Details:")
            for line in raw.splitlines():
                body_lines.append(f"    {line}")

    if notes:
        body_lines.append("")
        body_lines.append("Notes:")
        for dev, fs, mnt, reason, raw in notes:
            body_lines.append(f"- {dev} ({fs}) mount={mnt} note={reason}")

    body_lines.append("")
    body_lines.append(expl)
    body_lines.append("Suggested actions:")
    body_lines.append("- Ensure clean shutdowns and stable power.")
    body_lines.append("- If the issue persists, unmount the filesystem and run fsck in repair mode.")

    body = "\n".join(body_lines)
    send_smtp(cfg, subject, body)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        # Best-effort: avoid cron spam loops with huge tracebacks
        msg = f"partition-health-check failed: {e}"
        sys.stderr.write(msg + "\n")
        sys.exit(2)
