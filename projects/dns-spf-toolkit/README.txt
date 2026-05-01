DNS SYNC FOLDER
===============================================

ROOT
-----------------------------------------------
Run_All_Reports.bat   - main entry point, opens a menu:
                        1. Run reports for all clients (then pushes to GitHub)
                        2. Set up monthly scheduled task (automates option 1)
Sync_All_Bats.bat     - pushes per-client bat to every client folder

CLIENT SETUP
-----------------------------------------------
Client Setup\Setup_New_Client.bat - copy into a new client folder and run
                                    creates DNS Records, config.txt, online lookup

SCRIPTS (do not run directly)
-----------------------------------------------
Scripts\!Run_DNS_Records.bat      - per-client template, gets synced to clients
Scripts\DNS_Check.ps1             - reads config, writes DNS.txt
Scripts\SPF_Depth_Check.ps1       - reads config, writes SPF Depth.txt
Scripts\Sync_URLs.ps1             - rebuilds online lookup .url shortcuts
Scripts\Sync_Bats.ps1             - pushes per-client bat to all clients
Scripts\Build_Report.ps1          - scans all client txts, builds failure report
Scripts\Setup_New_Client.ps1      - called by Setup_New_Client.bat

AUTOMATION
-----------------------------------------------
Automation\Setup_Task_Scheduler.ps1  - registers monthly Task Scheduler job
                                       (called from Run_All_Reports.bat option 2)
Automation\Push_Report_to_GitHub.ps1 - pushes failure report to GitHub after each run
                                       token file: %USERPROFILE%\github_token.txt

REPORTS
-----------------------------------------------
Reports\DNS_Failure_Report_LATEST.txt - newest report (also pushed to GitHub)
Reports\DNS_Failure_Report_<date>.txt - timestamped archive (last 5 kept)

View latest report online:
https://github.com/X1ndy02/Home_Lab_1.0/blob/main/projects/dns-spf-toolkit/Reports/DNS_Failure_Report_LATEST.txt

WORKFLOWS
-----------------------------------------------
Run all clients        - open Run_All_Reports.bat, choose 1
Run one client         - click !Run_DNS_Records.bat in that client folder
Update scripts         - edit in Scripts\ then run Sync_All_Bats.bat if bat changed
Onboard new client     - copy Client Setup\Setup_New_Client.bat into new folder, run
Set up monthly schedule- open Run_All_Reports.bat as Administrator, choose 2

REPORT FORMAT
-----------------------------------------------
The failure report only shows clients with problems. OK clients are hidden.

Example:

  DNS FAILURE REPORT
  Generated : 01 May 2026  09:00:12
  Clients   : 12 scanned, 3 with issues
  ============================================================

  ClientA              clienta DNS.txt       No DMARC, No DKIM
  ClientB              clientb SPF Depth.txt SPF FAIL 13/10
  ClientC              clientc DNS.txt       DNS changes detected

  ============================================================

Issue codes:
  No SPF              - domain has no SPF record
  No DMARC            - domain has no DMARC record
  No DKIM             - no DKIM found for common selectors
  SPF FAIL x/10       - SPF lookup depth exceeds RFC limit of 10
  SPF WARN x/10       - SPF lookup depth at 8 or 9, close to limit
  Duplicate: x        - same include appears more than once in SPF chain
  DNS changes detected - records changed since last run
  +all DANGEROUS      - SPF record allows all senders (critical misconfiguration)
