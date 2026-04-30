# DNS & SPF Toolkit

A set of PowerShell scripts for checking DNS health and SPF record depth across client domains. Built for MSP/IT use — runs on Windows, deploys per client via a shared network drive.

---

## What it does

### DNS Health Report (`Scripts/DNS_Report.ps1`)
Pulls and reports on all key DNS records for a domain:
- **A** — IP address
- **MX** — mail servers and priority
- **NS** — name servers
- **SPF** — full record, authorized senders, and policy (hard fail / soft fail / dangerous)
- **DMARC** — policy, coverage %, reporting addresses, alignment
- **DKIM** — checks common selectors (selector1, selector2, google, k1, mail, default, dkim)
- **MTA-STS** — presence check

Saves a formatted `.txt` report and **detects changes** since the last run — flags anything added or removed.

### SPF Depth Checker (`Scripts/SPF_Depth_Check.ps1`)
SPF records have a hard RFC limit of **10 DNS lookups**. Going over causes legitimate email to fail silently.

This script:
- Counts total lookup depth recursively across all `include:` chains
- Flags status: `OK`, `WARN` (≥8), or `FAIL` (>10)
- Draws the full include tree so you can see exactly where the depth comes from
- Detects **duplicate includes**
- Lists all resolved IP ranges per include

### Sync Scripts (`Sync_DNS_Scripts.ps1` / `Sync_DNS_Scripts.bat`)
Pushes the latest version of the scripts from your master folder out to every client folder on the network share. Verifies each file with an MD5 hash after copying.

### Sync Online Lookup (`Sync_Online_Lookup.ps1`)
Reads `config.txt` and generates MXToolbox shortcut `.url` files (SPF, DMARC, DKIM) for each domain into an `Online Lookup/` folder. One click to open the right MXToolbox check for any client.

---

## Folder structure

```
dns-spf-toolkit/
├── Scripts/
│   ├── DNS_Report.ps1
│   ├── SPF_Depth_Check.ps1
│   └── config.txt
├── Examples/
│   ├── Example_DNS.txt
│   ├── Example_SPF_Depth.txt
│   └── Example_Client_Folder.txt
├── Run_DNS_Records.bat
├── Run_All_Clients.bat
├── Sync_DNS_Scripts.bat
├── Sync_DNS_Scripts.ps1
└── Sync_Online_Lookup.ps1
```

Per-client deployment on the network share:

```
\\SERVER\shared\!Client Infrastructure Information\
└── ClientName\
    └── DNS Records\
        ├── Scripts\
        │   ├── config.txt        ← add client domains here
        │   ├── DNS_Report.ps1
        │   └── SPF_Depth_Check.ps1
        ├── Online Lookup\
        │   ├── ClientName_SPF.url
        │   ├── ClientName_DMARC.url
        │   └── ClientName_DKIM.url
        ├── ClientName DNS.txt    ← generated report
        ├── ClientName SPF Depth.txt
        └── Run_DNS_Records.bat
```

---

## Usage

### Run checks for a single client
Double-click `Run_DNS_Records.bat` inside the client's `DNS Records\` folder.  
Reports are saved one level up from the `Scripts\` folder.

### Run checks for all clients at once
Edit `Run_All_Clients.bat` — set `CLIENTS_DIR` to your network share path, then run it.  
It loops through every client folder that has a `Run_DNS_Records.bat` and runs it.

### Add a domain
Edit `Scripts\config.txt` and add a line:
```
domain=example.com.au
```
Multiple domains supported — one per line.

### Push updated scripts to all clients
Run `Sync_DNS_Scripts.bat` from the master folder.  
It copies `DNS_Report.ps1` and `SPF_Depth_Check.ps1` to every client on the share and verifies with MD5.

### Generate MXToolbox shortcuts
Run `Sync_Online_Lookup.ps1` from inside a client's `Scripts\` folder.  
Creates `.url` shortcut files in `Online Lookup\` for quick browser access to SPF, DMARC, and DKIM checks.

---

## Example output

See the `Examples/` folder for sample DNS report and SPF depth check output.
