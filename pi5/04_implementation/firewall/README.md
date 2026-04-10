Firewall Implementation

System view

- no UFW or nftables policy is in use — Docker manages its own nftables NAT chains
- host-level iptables rules are used to restrict specific services to ZeroTier only
- VNC and RDP were running and internet-exposed — both disabled 2026-04-10
- Home Assistant (8123) and go2rtc (18555) restricted to ZeroTier via iptables on 2026-04-10

Port exposure summary

| Port | Service | Accessible from |
|------|---------|----------------|
| 22 | SSH | All interfaces (Fail2Ban active) |
| 80 | Nextcloud HTTP | Public — redirects to HTTPS |
| 443 | Nextcloud HTTPS | Public |
| 3000 | Grafana | ZeroTier only (10.244.10.4) |
| 8080 | ntfy | ZeroTier only (10.244.10.4) |
| 8123 | Home Assistant | ZeroTier only (iptables block) |
| 9443 | Portainer | ZeroTier only (10.244.10.4) |
| 9993 | ZeroTier | All interfaces (expected) |
| 18555 | go2rtc (HA) | ZeroTier only (iptables block) |

What interacts with what

- Docker controls NAT rules for all container ports via nftables
- `rules-homeassistant.sh` applies iptables INPUT rules to block HA and go2rtc from non-ZeroTier sources
- `iptables-ha-restrict.service` runs the script at boot after network and ZeroTier are up
- Fail2Ban handles SSH brute-force via iptables bans

Why this design

- Docker bypasses UFW/nftables policy rules, so per-service iptables INPUT rules are used instead
- ZeroTier-bound ports (Grafana, Portainer, ntfy) are restricted at the bind level — no extra rules needed
- HA uses host networking so it cannot be bound to a specific interface in the compose file — iptables is the only option
- SSH remains on all interfaces until key authentication is confirmed working, at which point it can be restricted to ZeroTier

Remaining exposure

- SSH (22) still public — will be restricted to ZeroTier once key auth is set up
- Nextcloud (80/443) intentionally public — required for external file sync access

What is here

- [rules-homeassistant.sh](rules-homeassistant.sh): iptables rules restricting HA and go2rtc to ZeroTier
- [iptables-ha-restrict.service](iptables-ha-restrict.service): systemd unit to apply rules at boot
