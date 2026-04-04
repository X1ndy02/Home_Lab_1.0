#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse


class ArchiveWorkflowError(RuntimeError):
    def __init__(self, kind, message):
        super().__init__(message)
        self.kind = kind


SOURCES = {
    "backup_status": {
        "kind": "report",
        "base": "pi5/03_reports/03_reports/01_system_reports/backup_status",
        "run_dir": "{date}/{stamp}_{slug}",
    },
    "pi_monitor_weekly": {
        "kind": "report",
        "base": "pi5/03_reports/03_reports/01_system_reports/pi_monitor_summaries",
        "run_dir": "weekly-{date}",
    },
    "pi_monitor_monthly": {
        "kind": "report",
        "base": "pi5/03_reports/03_reports/01_system_reports/pi_monitor_summaries",
        "run_dir": "{year_month}",
    },
    "grafana_weekly": {
        "kind": "report",
        "base": "pi5/03_reports/03_reports/01_system_reports/grafana_reports",
        "run_dir": "weekly-{date}",
    },
    "grafana_monthly": {
        "kind": "report",
        "base": "pi5/03_reports/03_reports/01_system_reports/grafana_reports",
        "run_dir": "{year_month}",
    },
    "smart_weekly": {
        "kind": "report",
        "base": "pi5/03_reports/03_reports/01_system_reports/smart_reports",
        "run_dir": "{date}",
    },
    "fail2ban_monthly": {
        "kind": "report",
        "base": "pi5/03_reports/03_reports/01_system_reports/fail2ban_reports",
        "run_dir": "{year_month}",
    },
    "ups_monthly": {
        "kind": "report",
        "base": "pi5/03_reports/03_reports/01_system_reports/ups_reports",
        "run_dir": "{year_month}",
    },
    "misc_report": {
        "kind": "report",
        "base": "pi5/03_reports/03_reports/01_system_reports/misc_reports",
        "run_dir": "{date}/{stamp}_{slug}",
    },
    "pi_monitor_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_reports/02_system_alerts/pi_monitor",
    },
    "fail2ban_ban_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_reports/02_system_alerts/fail2ban",
    },
    "ups_power_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_reports/02_system_alerts/ups_power",
    },
    "ups_shutdown_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_reports/02_system_alerts/ups_shutdown",
    },
    "partition_health_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_reports/02_system_alerts/partition_health",
    },
    "network_failover_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_reports/02_system_alerts/network_failover",
    },
    "misc_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_reports/02_system_alerts/misc_alerts",
    },
}


def parse_args():
    p = argparse.ArgumentParser(
        description="Archive a sent SMTP message into the repo and optionally commit/push it."
    )
    p.add_argument("--repo", default=".", help="Path to the git repository root")
    p.add_argument("--source", required=True, choices=sorted(SOURCES.keys()))
    p.add_argument("--timestamp", help="ISO timestamp for the mail event")
    p.add_argument("--from-addr", required=True)
    p.add_argument("--to-addr", required=True)
    p.add_argument("--subject", required=True)
    p.add_argument("--body")
    p.add_argument("--body-file")
    p.add_argument("--attach", action="append", default=[], help="Attach/copy a file")
    p.add_argument(
        "--attach-dir",
        action="append",
        default=[],
        help="Copy all files from a directory into the archive entry",
    )
    p.add_argument("--git-remote", default="origin")
    p.add_argument("--git-branch", default="main")
    p.add_argument("--push", action="store_true", help="Push after commit")
    p.add_argument(
        "--no-commit",
        action="store_true",
        help="Write files only; do not create a git commit",
    )
    p.add_argument(
        "--stdin-body",
        action="store_true",
        help="Read the email body from stdin",
    )
    return p.parse_args()


def parse_timestamp(raw):
    if not raw:
        return datetime.now().astimezone()
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    return datetime.fromisoformat(raw)


def slugify(value):
    value = value.lower()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_")
    return value or "message"


def read_body(args):
    if args.body_file:
        return Path(args.body_file).read_text(encoding="utf-8")
    if args.stdin_body:
        return sys.stdin.read()
    return args.body or ""


def collect_attachment_paths(args):
    paths = []
    for item in args.attach:
        path = Path(item)
        if not path.exists() or not path.is_file():
            raise SystemExit(f"Attachment file not found: {path}")
        paths.append(path)
    for item in args.attach_dir:
        path = Path(item)
        if not path.exists() or not path.is_dir():
            raise SystemExit(f"Attachment directory not found: {path}")
        for child in sorted(path.iterdir()):
            if child.is_file():
                paths.append(child)
    return paths


def resolve_target(repo_root, source_id, dt, subject, has_attachments):
    cfg = SOURCES[source_id]
    base = repo_root / cfg["base"]
    if cfg["kind"] == "report":
        run_dir = cfg["run_dir"].format(
            date=dt.strftime("%Y-%m-%d"),
            year_month=dt.strftime("%Y-%m"),
            stamp=dt.strftime("%Y-%m-%dT%H-%M-%S"),
            slug=slugify(subject),
        )
        target_dir = base / run_dir
        email_path = target_dir / "email.txt"
        return target_dir, email_path

    month_dir = base / dt.strftime("%Y-%m")
    stamp = dt.strftime("%Y-%m-%dT%H-%M-%S")
    slug = slugify(subject)
    if has_attachments:
        target_dir = month_dir / f"{stamp}_{slug}"
        email_path = target_dir / "email.txt"
    else:
        target_dir = month_dir
        email_path = month_dir / f"{stamp}_{slug}.txt"
    return target_dir, email_path


def build_email_copy(source_id, dt, from_addr, to_addr, subject, body):
    lines = [
        f"Source: {source_id}",
        f"Date: {dt.isoformat()}",
        f"From: {from_addr}",
        f"To: {to_addr}",
        f"Subject: {subject}",
        "",
        body.rstrip(),
        "",
    ]
    return "\n".join(lines)


def ensure_parent(path):
    path.parent.mkdir(parents=True, exist_ok=True)


def write_archive(repo_root, source_id, dt, from_addr, to_addr, subject, body, attachments):
    target_dir, email_path = resolve_target(
        repo_root, source_id, dt, subject, has_attachments=bool(attachments)
    )
    target_dir.mkdir(parents=True, exist_ok=True)
    email_path.write_text(
        build_email_copy(source_id, dt, from_addr, to_addr, subject, body),
        encoding="utf-8",
    )

    copied = [email_path]
    if attachments:
        for attachment in attachments:
            dest = target_dir / attachment.name
            shutil.copy2(attachment, dest)
            copied.append(dest)

        links_path = target_dir / "attachments.md"
        links_lines = ["# Attachments", ""]
        for dest in copied[1:]:
            links_lines.append(f"- [{dest.name}]({dest.name})")
        links_path.write_text("\n".join(links_lines) + "\n", encoding="utf-8")
        copied.append(links_path)

    meta = {
        "source": source_id,
        "timestamp": dt.isoformat(),
        "from": from_addr,
        "to": to_addr,
        "subject": subject,
        "files": [str(path.relative_to(repo_root)) for path in copied],
    }
    meta_path = target_dir / "meta.json" if email_path.name == "email.txt" else None
    if meta_path:
        meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
        copied.append(meta_path)

    return copied


def run(cmd, cwd, env=None):
    result = subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stdout.strip() or "command failed")
    return result.stdout.strip()


def load_github_token():
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("SMTP_ARCHIVE_GITHUB_TOKEN")
    if token:
        return token.strip()

    token_file = os.environ.get("GITHUB_TOKEN_FILE") or os.environ.get("SMTP_ARCHIVE_GITHUB_TOKEN_FILE")
    if token_file:
        file_path = Path(token_file)
        if file_path.exists():
            return file_path.read_text(encoding="utf-8", errors="replace").strip()

    return ""


def get_push_target(repo_root, remote_name, branch):
    remote_url = run(["git", "remote", "get-url", remote_name], cwd=repo_root)
    token = load_github_token()
    if token and remote_url.startswith("https://"):
        parsed = urlparse(remote_url)
        path = parsed.path.lstrip("/")
        return (
            f"https://x-access-token:{token}@{parsed.netloc}/{path}",
            branch,
        )
    return remote_name, branch


def load_kv(path):
    cfg = {}
    file_path = Path(path)
    if not file_path.exists():
        return cfg
    for raw_line in file_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        cfg[key.strip()] = value.strip().strip('"')
    return cfg


def parse_msmtp_from(path):
    file_path = Path(path)
    if not file_path.exists():
        return ""
    for raw_line in file_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        key, value = parts
        if key == "from":
            return value.strip()
    return ""


def resolve_notify_config():
    cfg = {
        "to": os.environ.get("SMTP_ARCHIVE_NOTIFY_TO", "").strip(),
        "from": os.environ.get("SMTP_ARCHIVE_NOTIFY_FROM", "").strip(),
        "subject_prefix": os.environ.get("SMTP_ARCHIVE_NOTIFY_SUBJECT_PREFIX", "[SMTP Archive]").strip()
        or "[SMTP Archive]",
        "msmtp_conf": os.environ.get("SMTP_ARCHIVE_MSMTP_CONF", "").strip(),
    }

    if not cfg["to"] or not cfg["from"]:
        ups_cfg = load_kv("/etc/x120x/ups-notify.conf")
        if not cfg["to"]:
            cfg["to"] = ups_cfg.get("TO", "")
        if not cfg["from"]:
            cfg["from"] = ups_cfg.get("FROM", "")

    if not cfg["to"] or not cfg["from"]:
        fail2ban_cfg = load_kv("/etc/fail2ban/jail.local")
        if not cfg["to"]:
            cfg["to"] = fail2ban_cfg.get("destemail", "")
        if not cfg["from"]:
            cfg["from"] = fail2ban_cfg.get("sender", "")

    if not cfg["from"]:
        cfg["from"] = parse_msmtp_from("/etc/msmtprc") or parse_msmtp_from("/srv/monitoring/msmtp.conf")

    if not cfg["to"]:
        cfg["to"] = cfg["from"]

    return cfg


def resolve_mail_command(msmtp_conf=""):
    if msmtp_conf and shutil.which("msmtp"):
        return ["msmtp", "-C", msmtp_conf, "-t"]
    if shutil.which("sendmail"):
        return ["sendmail", "-t"]
    if shutil.which("msmtp"):
        return ["msmtp", "-t"]
    return None


def send_error_notification(script_name, context, error_text, failure_kind="archive_workflow"):
    cfg = resolve_notify_config()
    if not cfg["to"] or not cfg["from"]:
        return False

    mail_cmd = resolve_mail_command(cfg["msmtp_conf"])
    if not mail_cmd:
        return False

    host = socket.gethostname()
    now = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    if failure_kind == "git_push":
        subject = "Git push failed"
    else:
        subject = f"{cfg['subject_prefix']} FAILURE {script_name} on {host}"

    lines = [
        f"Script: {script_name}",
        f"Host: {host}",
        f"Time: {now}",
        f"Failure kind: {failure_kind}",
    ]
    for key in ("repo", "source", "subject", "push", "git_remote", "git_branch", "email_file"):
        value = context.get(key)
        if value:
            lines.append(f"{key}: {value}")
    lines.extend(
        [
            "",
            "Error:",
            error_text.strip() or "(no error text)",
            "",
            "This notification was sent because the SMTP archive workflow failed.",
        ]
    )
    body = "\n".join(lines)
    message = (
        f"From: {cfg['from']}\n"
        f"To: {cfg['to']}\n"
        f"Subject: {subject}\n"
        f"Date: {datetime.now().astimezone().strftime('%a, %d %b %Y %H:%M:%S %z')}\n"
        "\n"
        f"{body}\n"
    )

    result = subprocess.run(
        mail_cmd,
        input=message.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return result.returncode == 0


def git_commit_and_push(repo_root, files, source_id, dt, subject, remote_name, branch, do_push):
    rel_files = [str(path.relative_to(repo_root)) for path in files]
    run(["git", "add", "-f", "--", *rel_files], cwd=repo_root)

    diff_proc = subprocess.run(
        ["git", "diff", "--cached", "--quiet"],
        cwd=repo_root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if diff_proc.returncode == 0:
        return

    short_subject = subject.strip().replace("\n", " ")
    commit_msg = f"Archive SMTP {source_id} {dt.strftime('%Y-%m-%d %H:%M')}: {short_subject}"
    run(["git", "commit", "-m", commit_msg], cwd=repo_root)

    if do_push:
        push_target, push_branch = get_push_target(repo_root, remote_name, branch)
        try:
            run(["git", "push", push_target, f"HEAD:{push_branch}"], cwd=repo_root)
        except RuntimeError as exc:
            raise ArchiveWorkflowError("git_push", str(exc)) from exc


def main():
    args = parse_args()
    repo_root = Path(args.repo).resolve()
    if not (repo_root / ".git").exists():
        raise SystemExit(f"Not a git repository: {repo_root}")

    dt = parse_timestamp(args.timestamp)
    body = read_body(args)
    attachments = collect_attachment_paths(args)
    files = write_archive(
        repo_root,
        args.source,
        dt,
        args.from_addr,
        args.to_addr,
        args.subject,
        body,
        attachments,
    )

    if not args.no_commit:
        git_commit_and_push(
            repo_root,
            files,
            args.source,
            dt,
            args.subject,
            args.git_remote,
            args.git_branch,
            args.push,
        )

    for path in files:
        print(path.relative_to(repo_root))


def cli():
    args = parse_args()
    context = {
        "repo": str(Path(args.repo).resolve()),
        "source": args.source,
        "subject": args.subject,
        "push": "yes" if args.push else "no",
        "git_remote": args.git_remote,
        "git_branch": args.git_branch,
    }
    try:
        repo_root = Path(args.repo).resolve()
        if not (repo_root / ".git").exists():
            raise SystemExit(f"Not a git repository: {repo_root}")

        dt = parse_timestamp(args.timestamp)
        body = read_body(args)
        attachments = collect_attachment_paths(args)
        files = write_archive(
            repo_root,
            args.source,
            dt,
            args.from_addr,
            args.to_addr,
            args.subject,
            body,
            attachments,
        )

        if not args.no_commit:
            git_commit_and_push(
                repo_root,
                files,
                args.source,
                dt,
                args.subject,
                args.git_remote,
                args.git_branch,
                args.push,
            )

        for path in files:
            print(path.relative_to(repo_root))
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
        if code:
            error_text = str(exc) or f"SystemExit({code})"
            failure_kind = getattr(exc, "kind", "archive_workflow")
            send_error_notification("smtp_archive.py", context, error_text, failure_kind=failure_kind)
        raise
    except Exception as exc:
        error_text = str(exc) or exc.__class__.__name__
        failure_kind = getattr(exc, "kind", "archive_workflow")
        send_error_notification("smtp_archive.py", context, error_text, failure_kind=failure_kind)
        raise


if __name__ == "__main__":
    cli()
