@echo off
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
echo  Pushing report to GitHub...
echo ============================================================
echo.

powershell.exe -ExecutionPolicy Bypass -File "%~dp0Automation\Push_Report_to_GitHub.ps1"

echo ============================================================
echo  All done.
echo ============================================================
pause
exit /b

:SETUP_TASK
echo.
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Automation\Setup_Task_Scheduler.ps1"
pause
exit /b
