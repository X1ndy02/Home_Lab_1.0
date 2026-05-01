@echo off
echo ============================================================
echo  Running DNS Records for all clients
echo ============================================================
echo.

set "CLIENTS_DIR=\\tngsrv01\shared\!Client Infrastructure Information"

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
