# Home_Lab_1.0

This repository documents and gradually captures the real implementation of my Raspberry Pi home lab.

The goal is to build operational knowledge by running services properly, monitoring them, securing them, backing them up, and validating failure and recovery behaviour on hardware I assembled and configured myself.

## Repository layout

- [pi5/](pi5) contains Raspberry Pi 5 documentation, reports, photos/screenshots, issues, and implementation exports.
- [pi0/](pi0) contains Raspberry Pi Zero hardware and software notes.
- [projects/](projects) contains related side projects built around the lab.

## Pi 5 overview

- [Hardware overview](pi5/01_overview/01_hardware.md)
- [Software overview](pi5/01_overview/02_software.md)
- [Monitoring and power management](pi5/01_overview/03_monitoring_power.md)
- [Security and backup](pi5/01_overview/04_security_backup.md)

## Pi 5 reports

- [Tracker](pi5/03_reports/01_tracker.md)
- [UPS shutdown report](pi5/03_reports/ups_natural_shutdown.md)
- [Improvement notes](pi5/03_reports/improvements_required.md)
- [SMTP report archive](pi5/03_reports/03_smtp/README.md)

## Implementation exports

The `pi5/04_implementation/` tree is reserved for structured copies of the live Pi 5 configuration and service files. Each subsystem is kept in its own folder so the repo can grow section by section without mixing documentation and runtime artifacts.

## Pi 5 issues

- [Improvement checklist](pi5/05_issues/01_improvement_checklist.md)
