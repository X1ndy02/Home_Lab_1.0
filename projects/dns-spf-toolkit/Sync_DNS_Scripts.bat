@echo off
powershell.exe -ExecutionPolicy Bypass -Command "Unblock-File -Path '%~dp0Sync_DNS_Scripts.ps1'; & '%~dp0Sync_DNS_Scripts.ps1'"
pause
