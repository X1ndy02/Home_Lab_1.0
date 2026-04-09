SSH Implementation

System view

- OpenSSH server running as a native systemd service
- listens on port 22 on all interfaces — LAN (192.168.1.181) and ZeroTier (10.244.10.4)
- password authentication is enabled
- public key authentication is enabled but no authorized keys are currently configured
- root login is restricted to key-only (`PermitRootLogin without-password`)
- Fail2Ban sshd jail is active and watching for repeated failures

SSH is the primary remote management path for the host.
All observed logins come from ZeroTier addresses (10.244.10.x), meaning access in practice travels over the VPN even though the port is open on the LAN.

What interacts with what

- OpenSSH accepts connections and authenticates against PAM and the local user database
- Fail2Ban watches the SSH journal for repeated failures and bans offending IPs at the firewall level
- ZeroTier provides the VPN tunnel used for normal remote access
- VNC and XRDP also provide remote access but as separate services alongside SSH

Why this design

- SSH is kept as the primary remote management path because it is lightweight and well understood
- password authentication remains enabled for convenience since the port is not directly internet-exposed behind the home router
- ZeroTier is used for remote access in practice, which keeps SSH traffic off the public internet without requiring firewall rule changes on the router
- Fail2Ban covers the case where a LAN device or VPN peer tries repeated logins

Flow

Access flow

- client connects to port 22 on any Pi interface
- sshd authenticates via password or public key
- successful login opens a session under the `xindy` user
- all sessions are logged to the system journal

Protection flow

- Fail2Ban reads sshd events from the system journal
- after repeated authentication failures, the offending IP is banned via iptables
- the recidive jail can escalate repeat offenders to longer bans

Trade-offs

- listening on all interfaces rather than ZeroTier-only means SSH is reachable from the LAN without VPN
- password authentication is weaker than key-only, but it is acceptable for a home lab not directly exposed to the internet
- no AllowUsers restriction means any valid local user account could attempt to log in
- X11Forwarding is enabled but not actively used
- MaxAuthTries is set to 6, which is higher than needed

What is here

- [service_model.md](service_model.md): authentication model, interface exposure, Fail2Ban integration
- [issues_and_improvements.md](../../05_issues/ssh.md): known weak points and next steps
- `config/`: sanitized copy of the active sshd configuration
