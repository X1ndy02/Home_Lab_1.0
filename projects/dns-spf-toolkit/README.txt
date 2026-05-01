DNS SYNC FOLDER
===============================================

ROOT
-----------------------------------------------
Run_All_Reports.bat   - runs DNS check on all clients then builds failure report
Sync_All_Bats.bat     - pushes per-client bat to every client folder

CLIENT SETUP
-----------------------------------------------
Client Setup\Setup_New_Client.bat - copy into a new client folder and run
                                    creates DNS Records, config.txt, online lookup

SCRIPTS (do not run directly)
-----------------------------------------------
Scripts\!Run_DNS_Records.bat  - per-client template, gets synced to clients
Scripts\DNS_Check.ps1         - reads config, writes DNS.txt
Scripts\SPF_Depth_Check.ps1   - reads config, writes SPF Depth.txt
Scripts\Sync_URLs.ps1         - rebuilds online lookup .url shortcuts
Scripts\Sync_Bats.ps1         - pushes per-client bat to all clients
Scripts\Build_Report.ps1      - scans all client txts, builds failure report
Scripts\Setup_New_Client.ps1  - called by Setup_New_Client.bat

REPORTS
-----------------------------------------------
Reports\DNS_Failure_Report_LATEST.txt - newest report
Reports\DNS_Failure_Report_<date>.txt - timestamped archive

WORKFLOWS
-----------------------------------------------
Run all clients     - click Run_All_Reports.bat
Run one client      - click !Run_DNS_Records.bat in that client folder
Update scripts      - edit in Scripts\ then run Sync_All_Bats.bat if bat changed
Onboard new client  - copy Client Setup\Setup_New_Client.bat into new folder, run
