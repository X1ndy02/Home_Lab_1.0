DNS & SPF Toolkit

System view

- PowerShell toolkit for checking DNS health and SPF record depth across client domains
- runs on Windows, structured for MSP and multi-client use
- two core scripts with separate concerns: record health and lookup depth
- built around a per-client folder structure that sits on a shared network drive

DNS misconfiguration is usually invisible until something breaks. Missing DMARC means spoofing goes unchecked. SPF over the 10-lookup limit causes legitimate mail to fail silently. This toolkit makes those issues visible before they become incidents.

What interacts with what

- config.txt drives both scripts — lists the domains to check, one per line
- DNS_Report.ps1 pulls live DNS records via Resolve-DnsName and saves a formatted report
- SPF_Depth_Check.ps1 walks the SPF include chain recursively and counts total lookup depth
- Run_DNS_Records.bat runs both scripts from a single double-click inside a client folder
- Run_All_Clients.bat loops across every client folder on a network share and runs each one
- Sync_DNS_Scripts.ps1 pushes updated scripts from the master folder to every client on the share and verifies each file with MD5
- Sync_Online_Lookup.ps1 reads config.txt and generates MXToolbox shortcut files for SPF, DMARC, and DKIM per domain

Why this design

- config.txt keeps domains separate from script logic so scripts can be updated and synced without touching client data
- per-client folder structure keeps reports and scripts together and scales to any number of clients without extra tooling
- change detection in DNS_Report.ps1 compares the current run against the last saved report, so only the bottom of each report needs reading to know if anything shifted
- SPF depth is a silent failure mode — RFC 7208 caps DNS lookups at 10, and going over causes mail rejection with no obvious error — flagging it early avoids that
- a single master copy of the scripts synced outward means no per-client maintenance when something changes

Flow

Single client flow

- add domain entries to Scripts/config.txt
- double-click Run_DNS_Records.bat inside the client's DNS Records folder
- DNS_Report.ps1 runs first and saves a formatted DNS health report one level up
- SPF_Depth_Check.ps1 runs second and saves a depth report with the full include tree
- on subsequent runs, each report includes a change section at the bottom comparing against the previous output

Multi-client flow

- Run_All_Clients.bat walks the configured network share path
- finds every client subfolder that contains a Run_DNS_Records.bat
- runs each one in sequence and reports which clients were run and which were skipped

Sync flow

- update scripts in the master Scripts/ folder
- run Sync_DNS_Scripts.bat from the master folder
- Sync_DNS_Scripts.ps1 copies DNS_Report.ps1, SPF_Depth_Check.ps1, and Run_DNS_Records.bat to every client on the share
- after copying, each file is verified against the source with an MD5 hash
- clients with no DNS Records/Scripts folder are skipped and listed

Trade-offs

- SPF depth check skips known slow or timeout-prone domains (sendgrid.net, bigpond.com, outlook.com, hotmail.com) — those still count as one lookup but are not resolved live
- DKIM check only tries common selectors (selector1, selector2, google, k1, mail, default, dkim) — custom selectors will not be found
- no scheduling built in — reports are only as current as the last manual run
- change detection compares against the last saved file, not a live baseline — a new client folder starts with "first run — baseline saved" and only tracks drift from that point forward

What is here

- Scripts/DNS_Report.ps1: pulls A, MX, NS, SPF, DMARC, DKIM, and MTA-STS records and saves a report with change detection
- Scripts/SPF_Depth_Check.ps1: walks the full SPF include tree, counts lookup depth, flags duplicates, and lists resolved IP ranges
- Scripts/config.txt: domain list — edit this per client to set which domains are checked
- Run_DNS_Records.bat: runs both scripts for the current client folder
- Run_All_Clients.bat: runs all client folders across the network share
- Sync_DNS_Scripts.bat: triggers the sync script
- Sync_DNS_Scripts.ps1: copies and verifies scripts across all client folders on the share
- Sync_Online_Lookup.ps1: generates MXToolbox shortcut files per domain from config.txt
- Examples/: sample output from DNS_Report.ps1 and SPF_Depth_Check.ps1, and an example of the expected client folder layout
