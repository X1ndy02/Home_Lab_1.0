# DNS Record Extractor
# Reads domains from config.txt in Scripts folder
# Saves reports to parent folder

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ParentDir  = Split-Path -Parent $ScriptDir
$ConfigFile = Join-Path $ScriptDir "config.txt"

$Domains = Get-Content $ConfigFile | Where-Object { $_ -match "^domain=" } | ForEach-Object { $_ -replace "^domain=", "" }

$DkimSelector = @('selector1','selector2','google','k1','mail','default','dkim')

foreach ($domain in $Domains) {

    $domainShort = $domain -replace '\.com\.au','' -replace '\.com','' -replace '\.au',''
        $today       = Get-Date -Format "dd MMM yyyy  HH:mm:ss"
    $outputFile  = Join-Path $ParentDir "$domainShort DNS.txt"

    $prevFile = if (Test-Path $outputFile) { Get-Content $outputFile } else { $null }

    $output = @(
        "DNS HEALTH REPORT",
        "Domain   : $domain",
        "Generated: $today",
        "------------------------------------------------------------",
        ""
    )

    # A RECORD
    $output += "A RECORD"
    $aResult = Resolve-DnsName -Name $domain -Type A -ErrorAction SilentlyContinue
    if ($aResult) { foreach ($e in $aResult) { $output += "  IP Address   : $($e.IPAddress)" } }
    else          { $output += "  Not found" }
    $output += ""

    # MX RECORD
    $output += "MX RECORD"
    $mxResult = Resolve-DnsName -Name $domain -Type MX -ErrorAction SilentlyContinue
    if ($mxResult) {
        foreach ($e in $mxResult) {
            $mx = if ($e.NameExchange) { $e.NameExchange } else { $e.Exchange }
            $output += "  Mail Server  : $mx"
            $output += "  Priority     : $($e.Preference)"
        }
    } else { $output += "  Not found" }
    $output += ""

    # NS RECORD
    $output += "NS RECORD"
    $nsResult = Resolve-DnsName -Name $domain -Type NS -ErrorAction SilentlyContinue
    if ($nsResult) { foreach ($e in $nsResult) { $output += "  Name Server  : $($e.NameHost)" } }
    else           { $output += "  Not found" }
    $output += ""

    # SPF
    $output += "SPF RECORD"
    $spfResult = Resolve-DnsName -Name $domain -Type TXT -ErrorAction SilentlyContinue |
                 Where-Object { ($_.Strings -join " ") -like "v=spf1*" }
    if ($spfResult) {
        foreach ($s in $spfResult) {
            $spftxt = $s.Strings -join " "
            $output += "  Record       : $spftxt"
            $includes = [regex]::Matches($spftxt, 'include:(\S+)')
            if ($includes.Count -gt 0) {
                $output += "  Authorized   :"
                foreach ($inc in $includes) { $output += "    $($inc.Groups[1].Value)" }
            }
            if ($spftxt -match '\-all')     { $output += "  Policy       : Hard Fail (-all)" }
            elseif ($spftxt -match '\~all') { $output += "  Policy       : Soft Fail (~all)" }
            elseif ($spftxt -match '\+all') { $output += "  Policy       : PASS ALL - DANGEROUS" }
        }
    } else { $output += "  FAIL - No SPF record found" }
    $output += ""

    # DMARC
    $output += "DMARC RECORD"
    $dmarcResult = Resolve-DnsName -Name "_dmarc.$domain" -Type TXT -ErrorAction SilentlyContinue
    if ($dmarcResult) {
        foreach ($d in $dmarcResult) {
            $txt = if ($d.Strings) { ($d.Strings -join " ") } else { ($d.Text -join " ") }
            $output += "  Record       : $txt"
            $output += ""
            if ($txt -match 'p=(\w+)')     { $output += "  Policy       : $($Matches[1])" }
            if ($txt -match 'pct=(\d+)')   { $output += "  Coverage     : $($Matches[1])%" }
            if ($txt -match 'rua=([^;]+)') { $output += "  Reports to   : $($Matches[1])" }
            if ($txt -match 'ruf=([^;]+)') { $output += "  Forensic to  : $($Matches[1])" }
            if ($txt -match 'adkim=(\w+)') { $output += "  DKIM Align   : $($Matches[1])" }
            if ($txt -match 'aspf=(\w+)')  { $output += "  SPF Align    : $($Matches[1])" }
        }
    } else { $output += "  FAIL - No DMARC record found" }
    $output += ""

    # DKIM
    $output += "DKIM RECORD"
    $dkimFound = $false
    foreach ($sel in $DkimSelector) {
        $dkimResult = Resolve-DnsName -Name "$sel._domainkey.$domain" -Type TXT -ErrorAction SilentlyContinue
        if ($dkimResult) {
            foreach ($d in $dkimResult) {
                $txt = if ($d.Strings) { ($d.Strings -join " ") } else { ($d.Text -join " ") }
                $output += "  Selector     : $sel"
                $output += "  Record       : $txt"
                $output += ""
            }
            $dkimFound = $true
        }
    }
    if (-not $dkimFound) { $output += "  WARN - No DKIM found for common selectors" }
    $output += ""

    # MTA-STS
    $output += "MTA-STS"
    $mtaResult = Resolve-DnsName -Name "_mta-sts.$domain" -Type TXT -ErrorAction SilentlyContinue
    if ($mtaResult) { foreach ($m in $mtaResult) { $output += "  Record       : $($m.Strings -join ' ')" } }
    else            { $output += "  Not configured" }
    $output += ""

    # CHANGE DETECTION
    $output += "CHANGES"
    if ($prevFile) {
        $currLines = $output | Where-Object { $_ -match "^\s+(IP|Mail|Name|Record|Policy|Coverage|Reports|Forensic|DKIM|SPF|MTA|Selector|Authorized)" }
        $prevLines = $prevFile | Where-Object { $_ -match "^\s+(IP|Mail|Name|Record|Policy|Coverage|Reports|Forensic|DKIM|SPF|MTA|Selector|Authorized)" }
        $added   = Compare-Object $prevLines $currLines | Where-Object { $_.SideIndicator -eq "=>" }
        $removed = Compare-Object $prevLines $currLines | Where-Object { $_.SideIndicator -eq "<=" }
        if ($added -or $removed) {
            $output += "  CHANGES DETECTED"
            foreach ($a in $added)   { $output += "  + $($a.InputObject.Trim())" }
            foreach ($r in $removed) { $output += "  - $($r.InputObject.Trim())" }
        } else {
            $output += "  No changes since last run"
        }
    } else {
        $output += "  First run - baseline saved"
    }

    $output += ""
    $output += "------------------------------------------------------------"
    $output | Out-File -FilePath $outputFile -Encoding UTF8 -Force
    Write-Host "Saved: $outputFile"
}

Write-Host ""
Write-Host "All done."
