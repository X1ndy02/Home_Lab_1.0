DNS & SPF Toolkit

System view

- PowerShell toolkit for checking DNS health and SPF record depth across client domains
- runs on Windows, structured for MSP and multi-client use
- scripts live in one central master folder and are called from each client folder by reference
- new clients can be onboarded in seconds with a single bat file

DNS misconfiguration is usually invisible until something breaks.
- Missing DMARC means spoofing goes unchecked.
- SPF over the 10-lookup limit causes legitimate mail to fail silently.
This toolkit makes those issues visible before they become incidents.

What interacts with what

- config.txt lives in each client's DNS Records folder — lists the domains to check, one per line
- DNS_Check.ps1 pulls live DNS records and saves a formatted report — called with ConfigFile and OutputDir params
- SPF_Depth_Check.ps1 walks the SPF include chain recursively and counts total lookup depth — same param model
- Sync_URLs.ps1 reads config.txt and generates MXToolbox shortcut files per domain into Online Lookup\
- !Run_DNS_Records.bat lives in each client folder — calls all three scripts above from the master Scripts\ location
- !Run_DNS_Records_Debug.bat is the same but runs visibly with output kept open for troubleshooting
- Run_All_Reports.bat loops every client folder on the share, runs each one, then calls Build_Report.ps1
- Build_Report.ps1 scans all client report files, flags issues, and saves a timestamped failure report
- Sync_Bats.ps1 pushes the latest !Run_DNS_Records.bat from master out to every client folder
- Setup_New_Client.ps1 builds the DNS Records folder, config.txt, and Online Lookup shortcuts for a new client

Why this design

- scripts live in one master location and are called by reference — updating a script instantly applies to all clients without syncing individual files
- ConfigFile and OutputDir params replace relative path assumptions, making scripts usable from anywhere
- Build_Report.ps1 gives a single-view summary across all clients — one report shows every client with issues without opening individual files
- Setup_New_Client automates the folder structure, config, and URL shortcuts so new clients are consistent and take seconds to onboard
- !Run_DNS_Records_Debug.bat exists alongside the normal bat so troubleshooting does not require editing the production file
- change detection in DNS_Check.ps1 compares the current run against the last saved report, so only the bottom of each report needs reading to know if anything shifted
- SPF depth is a silent failure mode — RFC 7208 caps DNS lookups at 10, and going over causes mail rejection with no obvious error — flagging it early avoids that

Flow

Single client flow

- add domain entries to config.txt in the client's DNS Records folder
- double-click !Run_DNS_Records.bat in that folder
- DNS_Check.ps1 runs and saves a DNS health report
- SPF_Depth_Check.ps1 runs and saves a depth report with the full include tree
- Sync_URLs.ps1 runs and regenerates Online Lookup shortcuts

All clients flow

- double-click Run_All_Reports.bat from the master DNS Sync Folder
- loops every client folder on the share and runs !Run_DNS_Records.bat in each one
- after all clients are done, Build_Report.ps1 runs and saves a failure summary

Failure report flow

- Build_Report.ps1 scans every client's DNS Records folder for .txt report files
- flags any FAIL, WARN, CHANGES DETECTED, or dangerous SPF policy lines
- saves a timestamped report and overwrites DNS_Failure_Report_LATEST.txt
- keeps the 5 most recent timestamped reports and removes older ones
- opens the report in Notepad on completion

New client onboarding flow

- copy Client Setup\Setup_New_Client.bat into the new client's folder on the share
- double-click it
- enter the client's domain(s) one by one when prompted
- script creates DNS Records\, config.txt, Online Lookup\ with MXToolbox shortcuts, and copies !Run_DNS_Records.bat from master

Sync flow

- edit scripts in the master Scripts\ folder as needed
- if !Run_DNS_Records.bat changed, run Sync_All_Bats.bat
- Sync_Bats.ps1 copies the bat to every client folder that has a DNS Records\ folder
- no sync needed for .ps1 files — they are always called directly from master

Trade-offs

- SPF depth check skips known slow or timeout-prone domains (sendgrid.net, bigpond.com, outlook.com, hotmail.com) — those still count as one lookup but are not resolved live
- DNS_Check.ps1 uses background jobs with a 5-second hard timeout per query to prevent hangs — a genuinely slow nameserver may return no result rather than wait
- DKIM check only tries common selectors (selector1, selector2, google, k1, mail, default, dkim) — custom selectors will not be found (working on this)
- no scheduling built in — reports are only as current as the last manual run (working on this)
- change detection compares against the last saved file — a new client starts with "first run — baseline saved" and only tracks drift from that point forward
- Build_Report.ps1 has the clients share path hardcoded — needs updating if the share moves

Master folder layout

```
DNS Sync Folder\
├── Client Setup\
│   ├── Setup_New_Client.bat    ← copy into new client folder and run
│   └── Setup_New_Client.ps1
├── Scripts\
│   ├── DNS_Check.ps1
│   ├── SPF_Depth_Check.ps1
│   ├── Sync_URLs.ps1
│   ├── Sync_Bats.ps1
│   ├── Build_Report.ps1
│   ├── !Run_DNS_Records.bat    ← per-client template, synced to clients
│   └── !Run_DNS_Records_Debug.bat
├── Reports\
│   ├── DNS_Failure_Report_LATEST.txt
│   └── DNS_Failure_Report_<timestamp>.txt
├── Run_All_Reports.bat
├── Sync_All_Bats.bat
└── README.txt
```

Client folder layout

```
\\SERVER\shared\!Client Infrastructure Information\
└── ClientName\
    └── DNS Records\
        ├── Online Lookup\
        │   ├── ClientName_SPF.url
        │   ├── ClientName_DMARC.url
        │   └── ClientName_DKIM.url
        ├── config.txt              ← add client domains here
        ├── ClientName DNS.txt      ← generated by DNS_Check.ps1
        ├── ClientName SPF Depth.txt← generated by SPF_Depth_Check.ps1
        └── !Run_DNS_Records.bat
```

The Online Lookup folder is populated by Sync_URLs.ps1. Each .url file opens the matching MXToolbox check directly in the browser for that client's domain.

Example output

DNS health report (ClientName DNS.txt)

```
DNS HEALTH REPORT
Domain   : example.com.au
Generated: 30 Apr 2026  17:24:07
------------------------------------------------------------

A RECORD
  IP Address   : 203.0.113.10

MX RECORD
  Mail Server  : smtp1.mail-provider.com
  Priority     : 10
  Mail Server  : smtp2.mail-provider.com
  Priority     : 20

NS RECORD
  Name Server  : ns1.registrar.net
  Name Server  : ns2.registrar.net
  Name Server  : ns3.registrar.net
  Name Server  : ns4.registrar.net

SPF RECORD
  Record       : v=spf1 ip4:203.0.113.10 include:spf.protection.outlook.com include:spf.mailprovider.com ~all
  Authorized   :
    spf.protection.outlook.com
    spf.mailprovider.com
  Policy       : Soft Fail (~all)

DMARC RECORD
  Record       : v=DMARC1; p=quarantine; rua=mailto:rua@example.com.au; pct=100; adkim=r; aspf=r
  Policy       : quarantine
  Coverage     : 100%
  Reports to   : mailto:rua@example.com.au
  DKIM Align   : r
  SPF Align    : r

DKIM RECORD
  WARN - No DKIM found for common selectors

MTA-STS
  Not configured

CHANGES
  No changes since last run

------------------------------------------------------------
```

SPF depth report (ClientName SPF Depth.txt)

```
example.com.au - SPF DEPTH CHECK - 30 Apr 2026
OK 4/10
------------------------------------------------------------

PRIMARY INCLUDES
------------------------------------------------------------
.-- spf.protection.outlook.com
|-- spf.mailprovider.com
|      nested: 2
-- spf.thirdparty.com

INCLUDES BREAKDOWN
------------------------------------------------------------
spf.mailprovider.com
-- mailgun.org
     |-- _spf.mailgun.org
     |    |-- _spf1.mailgun.org
     |    -- _spf2.mailgun.org

------------------------------------------------------------
TOTAL: 4/10 OK

spf.protection.outlook.com
  40.92.0.0/15
  40.107.0.0/16
  52.100.0.0/15
  104.47.0.0/17

spf.mailprovider.com
  192.0.2.0/24
  198.51.100.0/24

------------------------------------------------------------
```

Failure report (DNS_Failure_Report_LATEST.txt)

```
DNS FAILURE REPORT
Generated : 01 May 2026  13:42:38
Clients   : 8 scanned, 4 with issues
============================================================

ClientA              clienta DNS.txt      DNS changes detected
ClientB              clientb DNS.txt      No DMARC, No DKIM
ClientB              clientb SPF Depth.txt SPF FAIL 15/10
ClientC              clientc DNS.txt      No SPF, No DMARC, No DKIM
ClientD              clientd DNS.txt      No DKIM, DNS changes detected

============================================================
```

What is here

- Scripts/DNS_Check.ps1: pulls A, MX, NS, SPF, DMARC, DKIM, and MTA-STS records with hard timeouts and saves a report with change detection
- Scripts/SPF_Depth_Check.ps1: walks the full SPF include tree, counts lookup depth, flags duplicates, and lists resolved IP ranges
- Scripts/Build_Report.ps1: scans all client report files across the share and saves a consolidated failure summary
- Scripts/Sync_URLs.ps1: generates MXToolbox shortcut files per domain from config.txt
- Scripts/Sync_Bats.ps1: pushes !Run_DNS_Records.bat to every client folder on the share
- Scripts/!Run_DNS_Records.bat: per-client runner — calls DNS_Check, SPF_Depth_Check, and Sync_URLs from master
- Scripts/!Run_DNS_Records_Debug.bat: same as above but runs visibly with output kept open
- Client Setup/Setup_New_Client.bat: drop into a new client folder and run to onboard
- Client Setup/Setup_New_Client.ps1: builds folder structure, config.txt, Online Lookup shortcuts, and copies bat from master
- Run_All_Reports.bat: main entry point — option 1 runs all clients and builds the report, option 2 sets up the monthly scheduled task
- Sync_All_Bats.bat: triggers Sync_Bats.ps1 to push the bat to all clients
- README.txt: quick operational reference for daily use
- Examples/: sample output files and client folder layout reference
- Reports/DNS_Failure_Report_LATEST.txt: latest monthly report — pushed to GitHub on each automated run and viewable at github.com/X1ndy02/Home_Lab_1.0/blob/main/projects/dns-spf-toolkit/Reports/DNS_Failure_Report_LATEST.txt
