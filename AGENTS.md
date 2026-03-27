# Repository Guidelines

## Project Structure & Module Organization
This repo is a documentation-first Raspberry Pi home lab record. Keep top-level navigation in `README.md` aligned with the actual tree. Core Pi 5 overview docs live in `pi5/01_overview/`. Photos and screenshots belong in `pi5/02_photos_and_screenshots/`. Reports and operating notes live in `pi5/03_reports/`. Sanitized implementation exports belong under `pi5/04_implementation/`, grouped by subsystem such as `docker/`, `fail2ban/`, `ssh/`, and `restic/`. Track unfinished work in `pi5/05_issues/`. Pi Zero notes live under `pi0/`, and side projects go in `projects/`.

## Build, Test, and Development Commands
There is no build pipeline in this repo. Use lightweight checks before committing:

- `git status --short` to confirm the exact files changed.
- `git diff --stat` to review scope before pushing.
- `find pi5 -maxdepth 3 -type f | sort` to verify new docs are placed in the expected numbered section.
- `sed -n '1,120p' README.md` to confirm links and section names stay in sync after edits.

## Coding Style & Naming Conventions
Write concise Markdown with short sections, flat bullet lists, and relative links. Follow the existing naming pattern: numbered directories and files for ordered docs (`pi5/01_overview/04_security_backup.md`), snake_case for Markdown filenames, and lowercase subsystem folders in `pi5/04_implementation/`. Keep YAML, shell, and config examples sanitized; commit `.env.example` files, not real secrets.

## Testing Guidelines
There is no automated test suite yet. Treat validation as documentation QA: check links, confirm paths exist, and ensure copied configs match the described host layout. For scripts or config examples, prefer safe examples and note assumptions inline. Do not add unsanitized hostnames, credentials, API keys, tokens, or private IP details unless they are already intentionally public.

## Commit & Pull Request Guidelines
Recent history uses short imperative subjects such as `Update README.md`, `Add monitoring feedback item to checklist`, and `Document fail2ban implementation layout`. Keep commits focused on one area of the tree. PRs should summarize the affected subsystem, list any moved or renamed paths, mention security-sensitive changes explicitly, and include screenshots only when updating image-backed documentation or dashboard references.
