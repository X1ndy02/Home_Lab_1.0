# Home_Lab_1.0

This repository documents and gradually captures the real implementation of my Raspberry Pi home lab.

The goal is to build operational knowledge by running services properly, monitoring them, securing them, backing them up, and validating failure and recovery behaviour on hardware I assembled and configured myself.

## Repository layout

- [pi5/](pi5) contains Raspberry Pi 5 documentation, reports, photos/screenshots, issues, and implementation exports.
- [projects/](projects) contains related side projects built around the lab.

## Pi 5 overview

- [Hardware overview](pi5/01_overview/01_hardware.md)
- [Software overview](pi5/01_overview/02_software.md)
- [Monitoring and power management](pi5/01_overview/03_monitoring_power.md)
- [Security and backup](pi5/01_overview/04_security_backup.md)

## Pi 5 reports

- [Tracker](pi5/03_reports/tracker.md)
- [System reports](pi5/03_reports/01_system_reports)
- [System alerts](pi5/03_reports/02_system_alerts)

## Implementation exports

The `pi5/04_implementation/` tree holds structured copies of the live Pi 5 configuration and service files. Each subsystem has its own folder with a README, service model, and config references.

- [Docker](pi5/04_implementation/docker/)
- [Nextcloud](pi5/04_implementation/nextcloud/)
- [Monitoring](pi5/04_implementation/monitoring/)
- [Portainer](pi5/04_implementation/portainer/)
- [Fail2Ban](pi5/04_implementation/fail2ban/)
- [Restic](pi5/04_implementation/restic/)
- [SSH](pi5/04_implementation/ssh/)
- [SMART](pi5/04_implementation/smart/)
- [UPS](pi5/04_implementation/x120x_ups/)
- [Home Assistant](pi5/04_implementation/home_assistant/)

## Pi 5 issues

- [Improvement checklist](pi5/05_issues/01_improvement_checklist.md)
- [Issues index](pi5/05_issues/README.md)
