# ============================================================
# Register Monthly DNS Report Task in Windows Task Scheduler
# Run once as administrator to set up the scheduled task
# ============================================================

$TaskName    = "DNS Monthly Report"
$BatPath     = "\\YOUR-SERVER\shared\!Client Infrastructure Information\YOUR-MASTER-CLIENT\DNS Records\DNS Sync Folder\Run_All_Reports.bat"
$Description = "Runs DNS checks on all clients, builds failure report, and pushes to GitHub"
$TriggerDay  = 1       # day of month to run
$TriggerTime = "09:00" # time to run

$action   = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$BatPath`""
$trigger  = New-ScheduledTaskTrigger -Monthly -DaysOfMonth $TriggerDay -At $TriggerTime
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -RunOnlyIfNetworkAvailable `
    -StartWhenAvailable

try {
    Register-ScheduledTask `
        -TaskName    $TaskName `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -Description $Description `
        -Force | Out-Null

    Write-Host "============================================================"
    Write-Host " Task registered: $TaskName"
    Write-Host " Runs on        : day $TriggerDay of each month at $TriggerTime"
    Write-Host " Calls          : $BatPath"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "To verify: open Task Scheduler and look for '$TaskName'"
    Write-Host "To remove: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
} catch {
    Write-Host "ERROR: Failed to register task"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Make sure you are running this script as Administrator."
}
