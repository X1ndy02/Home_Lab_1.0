@echo off

REM When called with /auto (by Task Scheduler) — skips menu, runs all clients + builds report + pushes to GitHub
if /i "%1"=="/auto" goto AUTO

echo ============================================================
echo  DNS Toolkit
echo ============================================================
echo.
echo  1. Run reports for all clients
echo  2. Set up monthly scheduled task (run as Administrator)
echo.
set /p CHOICE="Choose option (1 or 2): "

if "%CHOICE%"=="2" goto SETUP_TASK
if "%CHOICE%"=="1" goto RUN_REPORTS
echo Invalid choice.
pause
exit /b

:RUN_REPORTS
echo.
echo ============================================================
echo  Running DNS Records for all clients
echo ============================================================
echo.

set "CLIENTS_DIR=\\YOUR-SERVER\shared\!Client Infrastructure Information"

for /d %%C in ("%CLIENTS_DIR%\*") do (
    if exist "%%C\DNS Records\!Run_DNS_Records.bat" (
        echo Running: %%~nxC
        pushd "%%C\DNS Records"
        call "%%C\DNS Records\!Run_DNS_Records.bat"
        popd
        echo Done: %%~nxC
        echo.
    ) else (
        echo Skipped: %%~nxC - no !Run_DNS_Records.bat found
    )
)

echo ============================================================
echo  Building failure report...
echo ============================================================
echo.

powershell.exe -ExecutionPolicy Bypass -File "%~dp0Scripts\Build_Report.ps1"

echo ============================================================
echo  All done.
echo ============================================================
pause
exit /b

:AUTO
echo.
echo ============================================================
echo  DNS Toolkit - Automated Monthly Run
echo ============================================================
echo.

set "CLIENTS_DIR=\\YOUR-SERVER\shared\!Client Infrastructure Information"

for /d %%C in ("%CLIENTS_DIR%\*") do (
    if exist "%%C\DNS Records\!Run_DNS_Records.bat" (
        pushd "%%C\DNS Records"
        call "%%C\DNS Records\!Run_DNS_Records.bat"
        popd
    )
)

powershell.exe -ExecutionPolicy Bypass -File "%~dp0Scripts\Build_Report.ps1"

powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ^
    "$token = (Get-Content '$env:USERPROFILE\github_token.txt' -Raw).Trim();" ^
    "$file = '%~dp0Reports\DNS_Failure_Report_LATEST.txt';" ^
    "$content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content $file -Raw -Encoding UTF8)));" ^
    "$headers = @{ Authorization = 'Bearer ' + $token; 'User-Agent' = 'dns-spf-toolkit' };" ^
    "$url = 'https://api.github.com/repos/X1ndy02/Home_Lab_1.0/contents/projects/dns-spf-toolkit/Reports/DNS_Failure_Report_LATEST.txt';" ^
    "try { $sha = (Invoke-RestMethod $url -Headers $headers).sha } catch { $sha = '' };" ^
    "$body = @{ message = 'DNS monthly report ' + (Get-Date -Format 'yyyy-MM-dd'); content = $content; branch = 'main' };" ^
    "if ($sha) { $body.sha = $sha };" ^
    "Invoke-RestMethod $url -Headers $headers -Method PUT -Body ($body | ConvertTo-Json -Depth 3) -ContentType 'application/json' | Out-Null;" ^
    "Write-Host 'Report pushed to GitHub.'"

exit /b

:SETUP_TASK
echo.
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ^
    "$bat = '%~dp0Run_All_Reports.bat';" ^
    "$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c \"' + $bat + '\" /auto');" ^
    "$trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At '09:00';" ^
    "$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -RunOnlyIfNetworkAvailable -StartWhenAvailable;" ^
    "Register-ScheduledTask -TaskName 'DNS Monthly Report' -Action $action -Trigger $trigger -Settings $settings -Description 'Monthly DNS check for all clients' -Force | Out-Null;" ^
    "Write-Host 'Task registered. Runs on the 1st of each month at 09:00.'"
pause
exit /b
