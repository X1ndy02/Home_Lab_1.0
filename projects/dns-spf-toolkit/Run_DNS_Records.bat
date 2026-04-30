@echo off
powershell.exe -ExecutionPolicy Bypass -Command "Unblock-File -Path '%~dp0Scripts\DNS_Report.ps1'; & '%~dp0Scripts\DNS_Report.ps1'; Unblock-File -Path '%~dp0Scripts\SPF_Depth_Check.ps1'; & '%~dp0Scripts\SPF_Depth_Check.ps1'"
