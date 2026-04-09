Issues And Improvements

Real issues already visible

Image is not pinned to a specific version
`ghcr.io/home-assistant/home-assistant:stable` updates on every `docker compose pull`.
A breaking change in a new release would take effect immediately on the next pull with no pinned version to roll back to.

Configuration is not backed up by Restic
The config directory at `/home/xindy/RaspPi5_Home_Lab/home-assistant/config/` is not in the Restic backup path.
It contains all integrations, device tokens, automation rules, and dashboards.
Losing the config directory means rebuilding the entire Home Assistant setup from scratch.

No health check defined
Docker reports the container as healthy as long as it is running.
A deadlocked or crashed Home Assistant process inside the container would not be detected.

Image version will drift
Using the `stable` tag means each pull may bring a new major or minor version.
Home Assistant has a history of breaking changes between versions.

Config lives outside this repo
The live configuration is in `RaspPi5_Home_Lab/` and is not sanitised or documented here.
If that repo is lost or out of date, there is no reference for what the setup looked like.

What I would change next

1. Add the Home Assistant config directory to the Restic backup exclusion review — confirm it is covered or explicitly add it.
2. Pin the image to a specific version tag after the next deliberate update so rollback is possible.
3. Add a health check — even a simple HTTP check against the Home Assistant API port would be better than none.
4. Document the key integrations and automation logic in this repo so the setup can be reconstructed if the config is lost.
