UPS Shutdown Validation

Related issue:
https://github.com/X1ndy02/RaspPi5_Home_Lab/issues/5

Date: 2026-03-10  
Shutdown threshold: 20%

Test scenario

I manually disconnected AC power while the system was running.  
The Pi continued running on UPS battery until it reached the shutdown threshold.

Before the test, everything was operating normally. Docker was running, MariaDB was active, monitoring was working, and the system was stable.

What happened

Power loss was detected correctly.  
A shutdown email was received.  
The shutdown sequence started at 19.8%, which matches the configured 20% threshold.

The quick backup process was triggered, but it failed.  
Logs show exit code 126 and a configuration parsing issue in ups-shutdown.conf (line 13).

Despite the backup failure, the shutdown sequence itself was clean:

- Docker stopped cleanly  
- containerd stopped cleanly  
- System reached poweroff target  
- Disks were synced  
- Journal stopped cleanly  

There were no forced kills or abrupt terminations.

After reboot

The system booted normally after restoring power.  
Filesystem check reported clean status.  
MariaDB started without crash recovery.  
Nextcloud became accessible.  
Monitoring services resumed automatically.

Email behaviour

The low battery shutdown email was received.  
Fail2Ban sent expected “service stopped” messages during shutdown.  
There was no msmtp log confirming the shutdown email.  
No AC_LOST event was recorded in the UPS event log.

Conclusion

The controlled shutdown mechanism works correctly.  
Service ordering is correct.  
Filesystem integrity is preserved.  
System recovery is successful.

However, the shutdown backup step failed and must be fixed before the system can be considered fully protected.

Next steps

Fix the ups-quick-backup.sh execution error (exit 126).  
Review ups-shutdown.conf line 13.  
Retest the full shutdown sequence after correction.




--------------------------------------------------

Required Improvements

1. Fix Shutdown Backup Execution (Critical)

The quick backup script failed with exit code 126.
No backup was created during shutdown.

Actions:
- Review ups-shutdown.conf (line 13).
- Correct command parsing issue.
- Validate ups-quick-backup.sh manually.
- Retest full shutdown after fix.

Priority: High  
Reason: Shutdown without backup defeats data protection objective.

--------------------------------------------------

2. Investigate Forced Container Termination

One container did not exit within the 10-second SIGTERM window.
Docker force-killed it (exit status 137).

Actions:
- Identify which container was force-killed.
- Inspect that container’s stop behaviour.
- Consider increasing Docker stop timeout if required.
- Verify graceful database and application shutdown timing.

Priority: Medium  
Reason: Forced termination increases risk of corruption under load.

--------------------------------------------------

3. Fix Missing AC_LOST Event Logging

No AC_LOST entry was recorded during this shutdown event.

Actions:
- Review UPS notify script logic.
- Confirm AC loss detection is logged before shutdown sequence.
- Validate log order during next test.

Priority: Medium  
Reason: Event logging must reflect real power events for audit reliability.

--------------------------------------------------

4. Improve Shutdown Email Consistency

Shutdown email exists but no corresponding msmtp log entry was found.

Actions:
- Verify email sending order relative to service stop.
- Ensure mail log persists before shutdown.
- Standardise shutdown notification format.

Priority: Low  
Reason: Observability improvement, not functional failure.

--------------------------------------------------

Overall System Status

Controlled shutdown: Working  
Service recovery: Working  
Filesystem integrity: Preserved  
Backup protection during shutdown: Not working  

System reliability is structurally sound, but backup execution must be corrected before considering the shutdown mechanism production-safe.
