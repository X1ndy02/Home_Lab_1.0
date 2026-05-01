@echo off
REM Copy this bat into a new client folder, then run it.
REM It calls the master setup PS1 and tells it to build DNS Records here.

set "MASTER_PS1=\\YOUR-SERVER\shared\!Client Infrastructure Information\YOUR-MASTER-CLIENT\DNS Records\DNS Sync Folder\Client Setup\Setup_New_Client.ps1"

set "CLIENT_PATH=%~dp0"
if "%CLIENT_PATH:~-1%"=="\" set "CLIENT_PATH=%CLIENT_PATH:~0,-1%"

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%MASTER_PS1%" -ClientPath "%CLIENT_PATH%"
pause
