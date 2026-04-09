Service Model

Host and service boundary

SSH runs on the host as a native systemd service, not inside Docker.

That is the right placement because SSH is the management path for the host itself.
If SSH ran inside a container, a broken Docker runtime would take away the primary way to get onto the machine.

Interface model

SSH listens on all interfaces:
- `0.0.0.0:22` — covers eth0 (192.168.1.181), wlan0 (192.168.1.183), and ZeroTier (10.244.10.4)
- `[::]:22` — IPv6 equivalent

In practice, all observed sessions originate from ZeroTier addresses (10.244.10.x).
The port is not forwarded at the router, so external internet access requires ZeroTier to be active on the connecting device.

Authentication model

Two methods are enabled:
- password authentication — active, used in practice
- public key authentication — enabled but no `authorized_keys` file is present

Root login is set to `without-password`, meaning root can only authenticate via key.
Since no key is configured, root login is effectively blocked.

`MaxAuthTries` is 6. `LoginGraceTime` is 120 seconds.
`PermitEmptyPasswords` is disabled.
`KbdInteractiveAuthentication` is disabled.

PAM is enabled and handles session management and password validation.

Fail2Ban integration

The sshd jail in Fail2Ban reads directly from the system journal.
Repeated failures within the detection window trigger an IP ban via iptables.
The recidive jail escalates repeat offenders over a longer time window.
All ban events generate email notifications.

Logging model

All authentication events — success and failure — are written to the system journal under the `ssh.service` unit.
These are the same log events that Fail2Ban monitors.
No separate log file is configured; journal is the source of truth.

Failure model

- if sshd crashes, the primary remote management path goes offline — no automatic fallback exists unless VNC or XRDP is still reachable
- if Fail2Ban loses journal access, the sshd jail stops detecting failures silently
- if ZeroTier goes down, SSH is still reachable from the LAN but not from outside the home network
- if password authentication is the only configured method and the account password changes, access is broken until corrected
