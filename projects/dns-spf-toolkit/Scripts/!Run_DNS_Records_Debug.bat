@echo off
REM DEBUG version - shows window, keeps it open, shows errors
REM Use this when troubleshooting

set "MASTER_DIR=\\tngsrv01\shared\!Client Infrastructure Information\010-TNG\DNS Records\DNS Sync Folder\Scripts"

set "CLIENT_PATH=%~dp0"
if "%CLIENT_PATH:~-1%"=="\" set "CLIENT_PATH=%CLIENT_PATH:~0,-1%"

echo Master dir   : %MASTER_DIR%
echo Client path  : %CLIENT_PATH%
echo Config file  : %CLIENT_PATH%\config.txt
echo.
echo ============================================================
echo Step 1: DNS_Check.ps1
echo ============================================================
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "& '%MASTER_DIR%\DNS_Check.ps1' -ConfigFile '%CLIENT_PATH%\config.txt' -OutputDir '%CLIENT_PATH%'"

echo.
echo ============================================================
echo Step 2: SPF_Depth_Check.ps1
echo ============================================================
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "& '%MASTER_DIR%\SPF_Depth_Check.ps1' -ConfigFile '%CLIENT_PATH%\config.txt' -OutputDir '%CLIENT_PATH%'"

echo.
echo ============================================================
echo Step 3: Sync_URLs.ps1
echo ============================================================
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "& '%MASTER_DIR%\Sync_URLs.ps1' -ConfigFile '%CLIENT_PATH%\config.txt' -OutputDir '%CLIENT_PATH%'"

echo.
echo ============================================================
echo Done.
echo ============================================================
pause
