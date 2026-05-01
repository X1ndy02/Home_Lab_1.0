# ============================================================
# SPF Lookup Depth Checker
# Reads domain from config file passed as parameter
# Writes report to OutputDir passed as parameter
# ============================================================

param(
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$OutputDir
)

if (-not (Test-Path $ConfigFile)) { Write-Host "Config not found: $ConfigFile"; return }
if (-not (Test-Path $OutputDir))  { Write-Host "Output dir not found: $OutputDir"; return }

$today = Get-Date -Format "dd MMM yyyy"

$Domains = Get-Content $ConfigFile | Where-Object { $_ -match "^domain=" } | ForEach-Object { $_ -replace "^domain=", "" }

# Cache to avoid querying same domain twice
$DnsCache = @{}

# Known slow/timeout domains - skip DNS query, count as 1 lookup
$SkipDomains = @('sendgrid.net','bigpond.com','outlook.com','hotmail.com')

function Get-SPFRecord($domain) {
    if ($DnsCache.ContainsKey($domain)) { return $DnsCache[$domain] }
    if ($SkipDomains -contains $domain) { $DnsCache[$domain] = $null; return $null }
    try {
        $records = Resolve-DnsName -Name $domain -Type TXT -ErrorAction SilentlyContinue
        foreach ($record in $records) {
            if (-not $record.Strings) { continue }
            $txt = ($record.Strings -join " ").Trim()
            if ($txt -like "v=spf1*") {
                if ($txt -match '^(v=spf1[^~\+\?-]*(?:[~\+\?-]all))') {
                    $result = $Matches[1].Trim()
                    $DnsCache[$domain] = $result
                    return $result
                }
                $DnsCache[$domain] = $txt
                return $txt
            }
        }
    } catch {}
    $DnsCache[$domain] = $null
    return $null
}

function Get-IPs($spf) {
    $ips = @()
    $spf.Split(' ') | ForEach-Object {
        if ($_ -match '^ip[46]:(.+)$') { $ips += $Matches[1] }
    }
    return $ips
}

function Get-Includes($spf) {
    $result = @([regex]::Matches($spf, '(?<![a-zA-Z])include:([a-zA-Z0-9._-]+)') | ForEach-Object { $_.Groups[1].Value })
    return ,$result
}

function Get-AllMechanisms($spf) {
    $items = @()
    [regex]::Matches($spf, '(?<![a-zA-Z])include:([a-zA-Z0-9._-]+)') | ForEach-Object {
        $items += [pscustomobject]@{ Type="include"; Value=$_.Groups[1].Value }
    }
    [regex]::Matches($spf, '(?<![a-zA-Z])a:([a-zA-Z0-9._-]+)') | ForEach-Object {
        $items += [pscustomobject]@{ Type="a"; Value=$_.Groups[1].Value }
    }
    [regex]::Matches($spf, '(?<![a-zA-Z])mx:([a-zA-Z0-9._-]+)') | ForEach-Object {
        $items += [pscustomobject]@{ Type="mx"; Value=$_.Groups[1].Value }
    }
    return ,$items
}

function Count-Lookups($domain, $visited) {
    if ($visited -contains $domain) { return 0 }
    $visited += $domain
    $spf = Get-SPFRecord $domain
    if (-not $spf) { return 1 }
    $count = 1
    foreach ($m in (Get-AllMechanisms $spf)) {
        if ($m.Type -eq "include") { $count += Count-Lookups $m.Value $visited }
        else { $count += 1 }
    }
    return $count
}

function Write-Tree($domain, $indent, $visited) {
    $lines    = @()
    $spf      = Get-SPFRecord $domain
    if (-not $spf) { return $lines }
    $includes = Get-Includes $spf
    $last     = $includes.Count - 1
    for ($i = 0; $i -lt $includes.Count; $i++) {
        $inc       = $includes[$i]
        $isLast    = ($i -eq $last)
        $branch    = if ($isLast) { "-- " } else { "|-- " }
        $lines    += "$indent$branch$inc"
        $newIndent = if ($isLast) { "$indent     " } else { "$indent|    " }
        if ($visited -notcontains $inc) {
            $visited += $inc
            $lines   += Write-Tree $inc $newIndent $visited
        }
    }
    return $lines
}

function Write-PrimaryTree($mechanisms) {
    $lines     = @()
    $last      = $mechanisms.Count - 1
    $incValues = $mechanisms | Where-Object { $_.Type -eq "include" } | ForEach-Object { $_.Value }
    $dupes     = $incValues | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }

    for ($i = 0; $i -lt $mechanisms.Count; $i++) {
        $m      = $mechanisms[$i]
        $isLast = ($i -eq $last)
        $branch = if ($i -eq 0) { ".-- " } elseif ($isLast) { "-- " } else { "|-- " }
        $label  = $m.Value
        $dupTag = if ($dupes -contains $m.Value) { "   !! DUPLICATE" } else { "" }

        if ($m.Type -eq "include") {
            $nested = (Count-Lookups $m.Value @()) - 1
            $lines += "$branch$label$dupTag"
            if ($nested -gt 0) {
                $pipe = if ($isLast) { "     " } else { "|     " }
                $lines += "$pipe nested: $nested"
            }
        } else {
            $lines += "$branch$label"
        }
    }
    return $lines
}

function Get-AllIPs($domain, $visited) {
    if ($visited -contains $domain) { return @() }
    $visited += $domain
    $spf  = Get-SPFRecord $domain
    if (-not $spf) { return @() }
    $ips  = Get-IPs $spf
    foreach ($inc in (Get-Includes $spf)) {
        $ips += Get-AllIPs $inc $visited
    }
    return $ips
}

foreach ($domain in $Domains) {
    $output = @()
    $spf = Get-SPFRecord $domain
    if (-not $spf) {
        $output += "$domain - SPF DEPTH CHECK - $today"
        $output += "FAIL - No SPF record found"
        $output += "TIP  - Check Online Lookup folder for direct MXToolbox link"
        $domainShort = $domain -replace '\.com\.au','' -replace '\.com','' -replace '\.au',''
        $outputFile  = Join-Path $OutputDir "$domainShort SPF Depth.txt"
        $output | Out-File -FilePath $outputFile -Encoding UTF8 -Force
        continue
    }

    $mechanisms = Get-AllMechanisms $spf
    $includes   = $mechanisms | Where-Object { $_.Type -eq "include" } | ForEach-Object { $_.Value }

    $total = 0
    foreach ($m in $mechanisms) {
        if ($m.Type -eq "include") { $total += Count-Lookups $m.Value @() }
        else { $total += 1 }
    }

    $dupes   = $includes | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
    $dupeStr = if ($dupes) { " | Duplicate: $($dupes -join ', ') x$($dupes.Count)" } else { "" }

    if ($total -gt 10)    { $status = "FAIL $total/10" }
    elseif ($total -ge 8) { $status = "WARN $total/10" }
    else                  { $status = "OK $total/10" }

    $output += "$domain - SPF DEPTH CHECK - $today"
    $output += "$status$dupeStr"
    $output += "------------------------------------------------------------"
    $output += ""

    $output += "PRIMARY INCLUDES"
    $output += "------------------------------------------------------------"
    $output += Write-PrimaryTree $mechanisms
    $output += ""

    $output += "INCLUDES BREAKDOWN"
    $output += "------------------------------------------------------------"
    $shownTree = @()
    foreach ($inc in ($includes | Select-Object -Unique)) {
        $incSpf = Get-SPFRecord $inc
        if ($incSpf -and (Get-Includes $incSpf).Count -gt 0 -and $shownTree -notcontains $inc) {
            $output    += $inc
            $output    += Write-Tree $inc "" @($inc)
            $output    += ""
            $shownTree += $inc
        }
    }
    $output += "------------------------------------------------------------"
    if ($total -gt 10)    { $output += "TOTAL: $total/10 FAIL - over by $($total - 10)" }
    elseif ($total -ge 8) { $output += "TOTAL: $total/10 WARN - close to limit" }
    else                  { $output += "TOTAL: $total/10 OK" }
    $output += ""

    foreach ($inc in ($includes | Select-Object -Unique)) {
        $ips = Get-AllIPs $inc @()
        $output += $inc
        if ($ips.Count -gt 0) {
            foreach ($ip in ($ips | Select-Object -Unique)) { $output += "  $ip" }
        } else {
            $output += "  (via includes only - no direct IPs)"
        }
        $output += ""
    }

    $output += "------------------------------------------------------------"
    $output += ""

    $domainShort = $domain -replace '\.com\.au','' -replace '\.com','' -replace '\.au',''
    $outputFile  = Join-Path $OutputDir "$domainShort SPF Depth.txt"
    $output | Out-File -FilePath $outputFile -Encoding UTF8 -Force
}
