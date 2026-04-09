Issues And Improvements

Real issues already visible

Password authentication is still enabled
All current logins use passwords, not keys.
Password authentication is weaker than key-based authentication even on a private network.
No `authorized_keys` file is configured, meaning there is no key-based fallback if a password is forgotten or changed.

Listening on all interfaces
SSH accepts connections from the full LAN as well as ZeroTier.
Restricting it to the ZeroTier interface only (`10.244.10.4`) would remove LAN exposure without affecting the way access actually works in practice.

No AllowUsers restriction
Any valid local account can attempt to authenticate.
Adding `AllowUsers xindy` would reduce the authentication surface without changing normal usage.

X11Forwarding is enabled but unused
X11 forwarding is on by default and has not been disabled.
It adds attack surface that is not needed for a headless management workflow.

MaxAuthTries is higher than needed
The current value of 6 gives more attempts per connection than necessary.
Lowering it to 3 would reduce the window for brute-force attempts before Fail2Ban acts.

What I would change next

1. Set up SSH key authentication — generate a key pair and add the public key to `~/.ssh/authorized_keys`, then test key login before disabling passwords.
2. Disable password authentication once key login is confirmed working.
3. Add `AllowUsers xindy` to restrict the authentication surface to the active account.
4. Disable X11Forwarding since it is not used.
5. Lower MaxAuthTries to 3.
6. Consider restricting the listen address to ZeroTier only once key auth is in place, so LAN exposure is removed entirely.
