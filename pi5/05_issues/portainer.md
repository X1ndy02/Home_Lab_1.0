Issues And Improvements

Current state

Portainer CE 2.39.1 installed 2026-04-09 and working.
Local Docker environment connected via socket. All stacks visible.

Known gaps

Socket access is fully privileged
The Docker socket mount gives Portainer root-equivalent access to the Docker runtime.
This is fine for a single-user lab but would need tighter scoping in a shared environment.

Port 9000 exposed on all LAN interfaces
HTTP access is available on the local network without TLS.
Acceptable for a home lab behind a router, but worth revisiting if network exposure changes.
HTTPS is available on port 9443.

Image version will drift if not actively maintained
Image is pinned to 2.39.1. Updates require a manual compose pull and recreate.
No automated update mechanism is in place.

What I would change next

1. Restrict port 9000 to ZeroTier only, matching how Grafana is now bound, so management UI is not on the LAN at all.
2. Set up a simple reminder or check to review Portainer updates when the rest of the stack is updated.
3. Evaluate whether the Portainer volume backup is covered by Restic or needs explicit inclusion.
