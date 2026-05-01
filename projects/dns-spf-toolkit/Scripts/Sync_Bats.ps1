# ============================================================
# Sync per-client bat to every client folder
# Reads template from this folder, pushes to every client
# ============================================================

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$BatTemplate = Join-Path $ScriptDir "!Run_DNS_Records.bat"
$ClientsDir  = "\\YOUR-SERVER\shared\!Client Infrastructure Information"

Write-Host "============================================================"
Write-Host " Syncing !Run_DNS_Records.bat to all client folders"
Write-Host "============================================================"
Write-Host "Template : $BatTemplate"
Write-Host "Clients  : $ClientsDir"
Write-Host ""

if (-not (Test-Path -LiteralPath $BatTemplate)) {
    Write-Host "ERROR: Template not found: $BatTemplate"
    exit
}

if (-not (Test-Path -LiteralPath $ClientsDir)) {
    Write-Host "ERROR: Clients folder not reachable: $ClientsDir"
    exit
}

$synced  = 0
$skipped = 0

Get-ChildItem -LiteralPath $ClientsDir -Directory | ForEach-Object {
    $dnsRecords = Join-Path $_.FullName "DNS Records"
    if (Test-Path -LiteralPath $dnsRecords) {
        $dest   = Join-Path $dnsRecords "!Run_DNS_Records.bat"
        $action = if (Test-Path -LiteralPath $dest) { "Replaced" } else { "Added" }
        Copy-Item -LiteralPath $BatTemplate -Destination $dest -Force
        Write-Host "  $action : $($_.Name)"
        $synced++
    } else {
        Write-Host "  Skipped : $($_.Name) (no DNS Records folder)"
        $skipped++
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Done. Synced: $synced   Skipped: $skipped"
Write-Host "============================================================"
