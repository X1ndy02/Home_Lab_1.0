@echo off
REM Per-client bat - lives in each client's DNS Records folder
REM Calls master PS1s, passes this folder as the working location
REM Master folder path is hardcoded below - update if master moves

set "MASTER_DIR=\\YOUR-SERVER\shared\!Client Infrastructure Information\YOUR-MASTER-CLIENT\DNS Records\DNS Sync Folder\Scripts"

set "CLIENT_PATH=%~dp0"
if "%CLIENT_PATH:~-1%"=="\" set "CLIENT_PATH=%CLIENT_PATH:~0,-1%"

start "" /min /wait powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "& '%MASTER_DIR%\DNS_Check.ps1' -ConfigFile '%CLIENT_PATH%\config.txt' -OutputDir '%CLIENT_PATH%'; & '%MASTER_DIR%\SPF_Depth_Check.ps1' -ConfigFile '%CLIENT_PATH%\config.txt' -OutputDir '%CLIENT_PATH%'; & '%MASTER_DIR%\Sync_URLs.ps1' -ConfigFile '%CLIENT_PATH%\config.txt' -OutputDir '%CLIENT_PATH%'"

echo DNS records updated.
timeout /t 1 /nobreak >nul
