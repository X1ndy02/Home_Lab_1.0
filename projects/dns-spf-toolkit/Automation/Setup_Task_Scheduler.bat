@echo off
REM Run as Administrator
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Setup_Task_Scheduler.ps1"
pause
