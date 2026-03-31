#!/usr/bin/env python3
import argparse
import re
import shutil
import sys
import tempfile
from email import policy
from email.parser import BytesParser
from email.utils import getaddresses, parsedate_to_datetime
from pathlib import Path

import smtp_archive


ALERT_HINTS = (
    "alert",
    "warn",
    "crit",
    "banned",
    "power event",
    "low battery",
    "failover",
    "dirty/unclean filesystem",
)


DETECTION_RULES = [
    ("fail2ban_ban_alert", re.compile(r"^\[fail2ban\].*\bbanned\b", re.I)),
    ("fail2ban_monthly", re.compile(r"^fail2ban monthly report\b", re.I)),
    ("backup_status", re.compile(r"^backup (success|failed|warning)\b", re.I)),
    ("pi_monitor_weekly", re.compile(r"^weekly pi monitor summary\b", re.I)),
    ("pi_monitor_monthly", re.compile(r"^monthly pi monitor summary\b", re.I)),
    ("grafana_weekly", re.compile(r"^\[pi weekly report\]", re.I)),
    ("grafana_monthly", re.compile(r"^\[pi monthly report\]", re.I)),
    ("smart_weekly", re.compile(r"^weekly smart summary\b", re.I)),
    ("ups_monthly", re.compile(r"monthly battery report\b", re.I)),
    ("partition_health_alert", re.compile(r"^alert:\s*dirty/unclean filesystem detected\b", re.I)),
    ("ups_power_alert", re.compile(r"\bpower event\b", re.I)),
    ("ups_shutdown_alert", re.compile(r"\blow battery\b.*\bshutting down\b", re.I)),
    ("network_failover_alert", re.compile(r"\bnetwork failover:", re.I)),
    ("pi_monitor_alert", re.compile(r"^\[pi monitor\](?:\s|$)", re.I)),
]


def parse_args():
    p = argparse.ArgumentParser(
        description="Parse a raw SMTP message, archive it into the repo, and optionally push it."
    )
    p.add_argument("--repo", default=".", help="Path to the git repository root")
    p.add_argument(
        "--source",
        default="auto",
        help="Explicit source ID or 'auto' to detect from subject/content",
    )
    p.add_argument("--email-file", help="Path to a raw RFC822 message")
    p.add_argument(
        "--stdin-email",
        action="store_true",
        help="Read the raw RFC822 message from stdin",
    )
    p.add_argument("--git-remote", default="origin")
    p.add_argument("--git-branch", default="main")
    p.add_argument("--push", action="store_true", help="Push after commit")
    p.add_argument(
        "--no-commit",
        action="store_true",
        help="Write files only; do not create a git commit",
    )
    return p.parse_args()


def load_raw_message(args):
    if args.email_file:
        return Path(args.email_file).read_bytes()
    if args.stdin_email:
        return sys.stdin.buffer.read()
    raise SystemExit("Provide --email-file or --stdin-email")


def decode_addresses(value):
    items = [addr for _name, addr in getaddresses([value or ""]) if addr]
    return ", ".join(items)


def parse_timestamp(msg):
    raw = msg.get("Date")
    if raw:
        try:
            return parsedate_to_datetime(raw)
        except Exception:
            pass
    return smtp_archive.parse_timestamp(None)


def sanitize_filename(name):
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._")
    return safe or "attachment.bin"


def strip_html(text):
    text = re.sub(r"(?is)<(script|style).*?>.*?</\1>", "", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = re.sub(r"[ \t]+", " ", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def extract_body(msg):
    plain_parts = []
    html_parts = []

    for part in msg.walk():
        if part.is_multipart():
            continue
        if part.get_filename():
            continue
        if part.get_content_disposition() == "attachment":
            continue
        ctype = part.get_content_type()
        try:
            content = part.get_content()
        except Exception:
            payload = part.get_payload(decode=True) or b""
            charset = part.get_content_charset() or "utf-8"
            content = payload.decode(charset, errors="replace")
        if ctype == "text/plain":
            plain_parts.append(content.strip())
        elif ctype == "text/html":
            html_parts.append(strip_html(content))

    if plain_parts:
        return "\n\n".join(part for part in plain_parts if part).strip()
    if html_parts:
        return "\n\n".join(part for part in html_parts if part).strip()
    return ""


def extract_attachments(msg, tmpdir):
    attachments = []
    counter = 0
    for part in msg.walk():
        if part.is_multipart():
            continue
        filename = part.get_filename()
        disposition = part.get_content_disposition()
        if not filename and disposition != "attachment":
            continue
        counter += 1
        if not filename:
            ext = part.get_content_subtype() or "bin"
            filename = f"attachment_{counter}.{ext}"
        path = Path(tmpdir) / sanitize_filename(filename)
        payload = part.get_payload(decode=True) or b""
        path.write_bytes(payload)
        attachments.append(path)
    return attachments


def detect_source(subject, body):
    subject = (subject or "").strip()
    for source_id, pattern in DETECTION_RULES:
        if pattern.search(subject):
            return source_id

    lowered = f"{subject}\n{body}".lower()
    for hint in ALERT_HINTS:
        if hint in lowered:
            return "misc_alert"
    return "misc_report"


def archive_from_message(repo_root, source_id, msg, body, attachments, push, no_commit, git_remote, git_branch):
    dt = parse_timestamp(msg)
    from_addr = decode_addresses(msg.get("From"))
    to_addr = decode_addresses(msg.get("To"))
    subject = (msg.get("Subject") or "").strip() or "(no subject)"

    files = smtp_archive.write_archive(
        repo_root,
        source_id,
        dt,
        from_addr or "unknown",
        to_addr or "unknown",
        subject,
        body,
        attachments,
    )

    if not no_commit:
        smtp_archive.git_commit_and_push(
            repo_root,
            files,
            source_id,
            dt,
            subject,
            git_remote,
            git_branch,
            push,
        )

    return files


def main():
    args = parse_args()
    repo_root = Path(args.repo).resolve()
    if not (repo_root / ".git").exists():
        raise SystemExit(f"Not a git repository: {repo_root}")

    if args.source != "auto" and args.source not in smtp_archive.SOURCES:
        choices = ", ".join(sorted(smtp_archive.SOURCES))
        raise SystemExit(f"Unknown source '{args.source}'. Known sources: {choices}")

    raw = load_raw_message(args)
    msg = BytesParser(policy=policy.default).parsebytes(raw)
    body = extract_body(msg)

    with tempfile.TemporaryDirectory(prefix="smtp-capture-") as tmpdir:
        attachments = extract_attachments(msg, tmpdir)
        source_id = args.source if args.source != "auto" else detect_source(msg.get("Subject"), body)
        files = archive_from_message(
            repo_root,
            source_id,
            msg,
            body,
            attachments,
            args.push,
            args.no_commit,
            args.git_remote,
            args.git_branch,
        )

    for path in files:
        print(path.relative_to(repo_root))


def cli():
    args = parse_args()
    context = {
        "repo": str(Path(args.repo).resolve()),
        "source": args.source,
        "push": "yes" if args.push else "no",
        "git_remote": args.git_remote,
        "git_branch": args.git_branch,
        "email_file": args.email_file or "stdin",
    }
    try:
        repo_root = Path(args.repo).resolve()
        if not (repo_root / ".git").exists():
            raise SystemExit(f"Not a git repository: {repo_root}")

        if args.source != "auto" and args.source not in smtp_archive.SOURCES:
            choices = ", ".join(sorted(smtp_archive.SOURCES))
            raise SystemExit(f"Unknown source '{args.source}'. Known sources: {choices}")

        raw = load_raw_message(args)
        msg = BytesParser(policy=policy.default).parsebytes(raw)
        body = extract_body(msg)

        with tempfile.TemporaryDirectory(prefix="smtp-capture-") as tmpdir:
            attachments = extract_attachments(msg, tmpdir)
            source_id = args.source if args.source != "auto" else detect_source(msg.get("Subject"), body)
            context["source"] = source_id
            context["subject"] = (msg.get("Subject") or "").strip() or "(no subject)"
            files = archive_from_message(
                repo_root,
                source_id,
                msg,
                body,
                attachments,
                args.push,
                args.no_commit,
                args.git_remote,
                args.git_branch,
            )

        for path in files:
            print(path.relative_to(repo_root))
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else 1
        if code:
            error_text = str(exc) or f"SystemExit({code})"
            failure_kind = getattr(exc, "kind", "archive_workflow")
            smtp_archive.send_error_notification(
                "smtp_capture_push.py",
                context,
                error_text,
                failure_kind=failure_kind,
            )
        raise
    except Exception as exc:
        error_text = str(exc) or exc.__class__.__name__
        failure_kind = getattr(exc, "kind", "archive_workflow")
        smtp_archive.send_error_notification(
            "smtp_capture_push.py",
            context,
            error_text,
            failure_kind=failure_kind,
        )
        raise


if __name__ == "__main__":
    cli()
