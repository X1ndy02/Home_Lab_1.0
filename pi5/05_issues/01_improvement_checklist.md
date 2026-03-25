Pi 5 Improvement Checklist

This file is for short practical items that still need work.

Current checklist

- Review secret handling across Docker-related configs and move sensitive values out of compose files where possible.
- Recheck shutdown behaviour for slow-exit containers and adjust stop timing if needed.
- Improve service health modelling so "container is running" is not treated as the same thing as "service is healthy".
- Bring remaining Docker-related configuration under the same `pi5` repo structure.

Notes

- Keep this file short and checklist-focused.
- Move detailed writeups into validation reports or implementation notes when needed.
