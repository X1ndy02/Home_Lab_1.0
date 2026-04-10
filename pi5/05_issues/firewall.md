Issues And Improvements

Real issues already visible

SSH still public on all interfaces
Port 22 accepts connections from all interfaces including public LAN.
Once SSH key authentication is confirmed working, the listen address should be restricted to ZeroTier only (10.244.10.4) so SSH is no longer reachable without VPN.

No firewall default-deny policy
The system has no UFW or nftables policy that defaults to deny.
Docker bypasses typical firewall policies by writing directly to nftables NAT chains.
Individual iptables rules are used to patch specific gaps but there is no unified policy.

iptables rules are not idempotent on restart
The current `rules-homeassistant.sh` uses `-I` (insert) and `-A` (append) without checking if rules already exist.
Running the script twice will duplicate rules.
This needs to be rewritten with a flush-and-reapply approach or converted to use `iptables-save` / `iptables-restore`.

go2rtc exposure
go2rtc (port 18555) is now blocked by iptables but still runs with host networking.
If iptables rules fail to apply at boot, it would be exposed again.
Long term, this should be configured to bind to the ZeroTier interface directly in the HA go2rtc config.

What I would change next

1. Set up SSH key auth and restrict port 22 to ZeroTier only — removes the last public management port.
2. Rewrite firewall rules to be idempotent — flush and reapply rather than insert and append.
3. Configure go2rtc to bind to ZeroTier interface directly, removing the iptables dependency for that service.
4. Audit regularly when new services are added — any new container with host networking or published ports should be reviewed.
