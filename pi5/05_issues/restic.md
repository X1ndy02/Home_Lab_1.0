Issues And Improvements

Real issues already visible

No verification step
The backup script does not run `restic check` after each backup.
Repository integrity is assumed rather than validated.
A corrupted snapshot would not be detected until a restore is attempted.
This applies to both the local and R2 repositories.

Mail delivery has no fallback
If msmtp fails to deliver the backup notification, the failure is silent.
The ntfy push notification acts as a partial fallback for the most critical outcomes, but mail delivery itself is not monitored.

Timer health is not monitored
The systemd timer drives the entire backup schedule.
If the timer is accidentally disabled or drifts, backups stop without any alert.
The pi-monitor checks are not currently watching restic timer state or last-run timestamp.

R2 offsite window is short
The R2 repository keeps only the last 2 snapshots.
This limits the offsite recovery point to 2 days.
Increasing to 3 or 4 would give a slightly longer window at minimal cost given R2's free tier limits.

What I would change next

1. Add `restic check` as a periodic step (weekly is enough) to validate local and R2 repository integrity rather than assuming it.
2. Extend the pi-monitor checks to include restic timer state and last-run timestamp so a missed backup becomes visible quickly.
3. Consider whether the snapshot size (~48 GiB logical) reflects what actually needs protecting, or whether a more selective backup path would be more efficient.
4. Monitor ntfy delivery alongside mail so there is always at least one working alert channel.
