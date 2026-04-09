Issues And Improvements

Real issues already visible

No offsite or remote copy
All snapshots live on the SATA SSD attached to the same machine being backed up.
A physical failure of that drive, or of the Pi itself, takes both the live system and the backup at the same time.
This is the most significant gap in the current backup design.

Retention window is short
Four snapshots at daily frequency gives a four-day recovery window.
If a silent data corruption or misconfiguration goes undetected for more than four days, it will have been pruned from all snapshots before it is noticed.

No verification step
The backup script does not run `restic check` after each backup.
Repository integrity is assumed rather than validated.
A corrupted snapshot would not be detected until a restore is attempted.

Mail delivery has no fallback
If msmtp fails to deliver the backup notification, the failure is silent.
There is no secondary alert channel, no SMS fallback, and no monitoring of mail delivery itself.

Timer health is not monitored
The systemd timer drives the entire backup schedule.
If the timer is accidentally disabled or drifts, backups stop without any alert.
The pi-monitor checks are not currently watching restic timer state.

What I would change next

1. Add a remote or offsite backup target — even a second local machine or an encrypted cloud target would remove the single point of failure.
2. Add `restic check` as a periodic step to validate repository integrity rather than assuming it.
3. Extend the pi-monitor checks to include restic timer state and last-run timestamp so a missed backup becomes visible quickly.
4. Review the retention policy — increasing to 7 or 14 snapshots would give a longer recovery window without a large storage cost given restic's deduplication.
5. Consider whether the snapshot size (~48 GiB) reflects what actually needs protecting, or whether a more selective backup path would be more efficient.
