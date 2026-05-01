# DNS Record Extractor
# Reads domain from config file passed as parameter
# Writes report to OutputDir passed as parameter
# All DNS queries have hard timeouts to prevent hangs

param(
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$OutputDir
)

if (-not (Test-Path -LiteralPath $ConfigFile)) { Write-Host "Config not found: $ConfigFile"; return }
if (-not (Test-Path -LiteralPath $OutputDir))  { Write-Host "Output dir not found: $OutputDir"; return }

$Domains = Get-Content -LiteralPath $ConfigFile | Where-Object { $_ -match "^domain=" } | ForEach-Object { $_ -replace "^domain=", "" }

$DkimSelector = @('selector1','selector2','google','k1','mail','default','dkim')

# Wrapper around Resolve-DnsName with hard timeout via background job
function Resolve-WithTimeout {
    param($Name, $Type, $TimeoutSec = 5)
    $job = Start-Job -ScriptBlock {
        param($n, $t)
        try { Resolve-DnsName -Name $n -Type $t -ErrorAction SilentlyContinue -DnsOnly }
        catch { $null }
    } -ArgumentList $Name, $Type

    if (Wait-Job $job -Timeout $TimeoutSec) {
        $result = Receive-Job $job
        Remove-Job $job -Force
        return $result
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return $null
    }
}

foreach ($domain in $Domains) {

    $domainShort = $domain -replace '\.com\.au','' -replace '\.com','' -replace '\.au',''
    $today       = Get-Date -Format "dd MMM yyyy  HH:mm:ss"
    $outputFile  = Join-Path $OutputDir "$domainShort DNS.txt"

    $prevFile = if (Test-Path -LiteralPath $outputFile) { Get-Content -LiteralPath $outputFile } else { $null }

    $output = @(
        "DNS HEALTH REPORT",
        "Domain   : $domain",
        "Generated: $today",
        "------------------------------------------------------------",
        ""
    )

    # A RECORD
    $output += "A RECORD"
    $aResult = Resolve-WithTimeout -Name $domain -Type A
    if ($aResult) { foreach ($e in $aResult) { if ($e.IPAddress) { $output += "  IP Address   : $($e.IPAddress)" } } }
    else          { $output += "  Not found" }
    $output += ""

    # MX RECORD
    $output += "MX RECORD"
    $mxResult = Resolve-WithTimeout -Name $domain -Type MX
    if ($mxResult) {
        foreach ($e in $mxResult) {
            $mx = if ($e.NameExchange) { $e.NameExchange } else { $e.Exchange }
            if ($mx) {
                $output += "  Mail Server  : $mx"
                $output += "  Priority     : $($e.Preference)"
            }
        }
    } else { $output += "  Not found" }
    $output += ""

    # NS RECORD
    $output += "NS RECORD"
    $nsResult = Resolve-WithTimeout -Name $domain -Type NS
    if ($nsResult) { foreach ($e in $nsResult) { if ($e.NameHost) { $output += "  Name Server  : $($e.NameHost)" } } }
    else           { $output += "  Not found" }
    $output += ""

    # SPF
    $output += "SPF RECORD"
    $txtResult = Resolve-WithTimeout -Name $domain -Type TXT
    $spfResult = $txtResult | Where-Object { ($_.Strings -join " ") -like "v=spf1*" }
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
    $dmarcResult = Resolve-WithTimeout -Name "_dmarc.$domain" -Type TXT
    if ($dmarcResult) {
        foreach ($d in $dmarcResult) {
            $txt = if ($d.Strings) { ($d.Strings -join " ") } else { ($d.Text -join " ") }
            if (-not $txt) { continue }
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
        $dkimResult = Resolve-WithTimeout -Name "$sel._domainkey.$domain" -Type TXT -TimeoutSec 3
        if ($dkimResult) {
            foreach ($d in $dkimResult) {
                $txt = if ($d.Strings) { ($d.Strings -join " ") } else { ($d.Text -join " ") }
                if (-not $txt) { continue }
                $output += "  Selector     : $sel"
                $output += "  Record       : $txt"
                $output += ""
                $dkimFound = $true
            }
        }
    }
    if (-not $dkimFound) { $output += "  WARN - No DKIM found for common selectors" }
    $output += ""

    # MTA-STS
    $output += "MTA-STS"
    $mtaResult = Resolve-WithTimeout -Name "_mta-sts.$domain" -Type TXT
    if ($mtaResult) { foreach ($m in $mtaResult) { if ($m.Strings) { $output += "  Record       : $($m.Strings -join ' ')" } } }
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
}
