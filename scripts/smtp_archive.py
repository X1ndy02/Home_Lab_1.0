#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse


SOURCES = {
    "pi_monitor_weekly": {
        "kind": "recurring",
        "base": "pi5/03_reports/03_smtp/recurring/pi_monitor_weekly",
        "run_dir": "{date}",
    },
    "pi_monitor_monthly": {
        "kind": "recurring",
        "base": "pi5/03_reports/03_smtp/recurring/pi_monitor_monthly",
        "run_dir": "{year_month}",
    },
    "grafana_weekly": {
        "kind": "recurring",
        "base": "pi5/03_reports/03_smtp/recurring/grafana_weekly",
        "run_dir": "weekly-{date}",
    },
    "grafana_monthly": {
        "kind": "recurring",
        "base": "pi5/03_reports/03_smtp/recurring/grafana_monthly",
        "run_dir": "{year_month}",
    },
    "smart_weekly": {
        "kind": "recurring",
        "base": "pi5/03_reports/03_smtp/recurring/smart_weekly",
        "run_dir": "{date}",
    },
    "fail2ban_monthly": {
        "kind": "recurring",
        "base": "pi5/03_reports/03_smtp/recurring/fail2ban_monthly",
        "run_dir": "{year_month}",
    },
    "ups_monthly": {
        "kind": "recurring",
        "base": "pi5/03_reports/03_smtp/recurring/ups_monthly",
        "run_dir": "{year_month}",
    },
    "pi_monitor_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_smtp/alerts/pi_monitor",
    },
    "ups_power_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_smtp/alerts/ups_power",
    },
    "ups_shutdown_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_smtp/alerts/ups_shutdown",
    },
    "partition_health_alert": {
        "kind": "alert",
        "base": "pi5/03_reports/03_smtp/alerts/partition_health",
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
    if cfg["kind"] == "recurring":
        run_dir = cfg["run_dir"].format(
            date=dt.strftime("%Y-%m-%d"),
            year_month=dt.strftime("%Y-%m"),
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


def get_push_target(repo_root, remote_name, branch):
    remote_url = run(["git", "remote", "get-url", remote_name], cwd=repo_root)
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("SMTP_ARCHIVE_GITHUB_TOKEN")
    if token and remote_url.startswith("https://"):
        parsed = urlparse(remote_url)
        path = parsed.path.lstrip("/")
        return (
            f"https://x-access-token:{token}@{parsed.netloc}/{path}",
            branch,
        )
    return remote_name, branch


def git_commit_and_push(repo_root, files, source_id, dt, subject, remote_name, branch, do_push):
    rel_files = [str(path.relative_to(repo_root)) for path in files]
    run(["git", "add", "--", *rel_files], cwd=repo_root)

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
        run(["git", "push", push_target, f"HEAD:{push_branch}"], cwd=repo_root)


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


if __name__ == "__main__":
    main()
