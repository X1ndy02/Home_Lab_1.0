# ============================================================
# Build DNS Failure Report
# Scans every client TXT output and flags any FAIL/WARN/CHANGES
# Saves report (timestamped + LATEST), keeps only 5 most recent
# Format: one line per client+file with issues, OK clients hidden
# ============================================================

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$MasterDir   = Split-Path -Parent $ScriptDir
$ClientsDir  = "\\tngsrv01\shared\!Client Infrastructure Information"
$ReportsDir  = Join-Path $MasterDir "Reports"

if (-not (Test-Path -LiteralPath $ReportsDir)) {
    New-Item -Path $ReportsDir -ItemType Directory -Force | Out-Null
}

$timestamp  = Get-Date -Format "yyyy-MM-dd_HHmm"
$today      = Get-Date -Format "dd MMM yyyy  HH:mm:ss"
$ReportFile = Join-Path $ReportsDir "DNS_Failure_Report_$timestamp.txt"
$LatestFile = Join-Path $ReportsDir "DNS_Failure_Report_LATEST.txt"

$lines = @()
$scanned = 0
$withIssues = 0

Get-ChildItem -LiteralPath $ClientsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $dnsRecords = Join-Path $_.FullName "DNS Records"
    if (-not (Test-Path -LiteralPath $dnsRecords)) { return }

    $scanned++
    $clientName = $_.Name

    $txtFiles = Get-ChildItem -LiteralPath $dnsRecords -Filter "*.txt" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne "config.txt" }

    foreach ($file in $txtFiles) {
        $content = Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        $fileIssues = @()

        foreach ($line in $content) {
            if ($line -match "FAIL\s+(\d+/10)")         { $fileIssues += "SPF FAIL $($Matches[1])" }
            if ($line -match "WARN\s+(\d+/10)")         { $fileIssues += "SPF WARN $($Matches[1])" }
            if ($line -match "Duplicate: ([^|]+)")       { $fileIssues += "Duplicate: $($Matches[1].Trim())" }
            if ($line -match "FAIL - No SPF record")    { $fileIssues += "No SPF" }
            if ($line -match "FAIL - No DMARC record")  { $fileIssues += "No DMARC" }
            if ($line -match "WARN - No DKIM found")    { $fileIssues += "No DKIM" }
            if ($line -match "CHANGES DETECTED")        { $fileIssues += "DNS changes detected" }
            if ($line -match "PASS ALL - DANGEROUS")    { $fileIssues += "+all DANGEROUS" }
        }

        $fileIssues = $fileIssues | Select-Object -Unique

        if ($fileIssues.Count -gt 0) {
            $clientCol = $clientName.PadRight(20)
            $fileCol   = $file.Name.PadRight(20)
            $issuesCol = ($fileIssues -join ", ")
            $lines += "$clientCol $fileCol $issuesCol"
            $withIssues++
        }
    }
}

# Build report
$report = @()
$report += "DNS FAILURE REPORT"
$report += "Generated : $today"
$report += "Clients   : $scanned scanned, $withIssues with issues"
$report += "============================================================"
$report += ""

if ($lines.Count -eq 0) {
    $report += "All clients OK - no failures, warnings, or changes detected."
} else {
    $report += $lines
}

$report += ""
$report += "============================================================"

$report | Out-File -FilePath $ReportFile -Encoding UTF8 -Force
$report | Out-File -FilePath $LatestFile -Encoding UTF8 -Force

# Cleanup - keep only 5 most recent timestamped reports (excluding LATEST)
Get-ChildItem -LiteralPath $ReportsDir -Filter "DNS_Failure_Report_*.txt" |
    Where-Object { $_.Name -ne "DNS_Failure_Report_LATEST.txt" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 5 |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

Write-Host "Report saved: $LatestFile"

Start-Process notepad.exe $LatestFile
