# ============================================================
# DNS Scripts Sync
# Runs from: C:\Users\YourName\Desktop\DNS-Health-Check
# Syncs to : \\YOUR-SERVER\shared\!Client Infrastructure Information\
# ============================================================

$MasterDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$MasterScripts = Join-Path $MasterDir "Scripts"
$MasterBat     = Join-Path $MasterDir "Run_DNS_Records.bat"
$ClientsDir    = "\\YOUR-SERVER\shared\!Client Infrastructure Information"

Write-Host "============================================================"
Write-Host " DNS Scripts Sync"
Write-Host "============================================================"
Write-Host ""
Write-Host "Master  : $MasterDir"
Write-Host "Target  : $ClientsDir"
Write-Host ""

# Get all ps1 files from master Scripts folder
$ps1Files = Get-ChildItem -Path $MasterScripts -Filter "*.ps1" -ErrorAction SilentlyContinue

if (-not $ps1Files) {
    Write-Host "No .ps1 files found in $MasterScripts"
    exit
}

$synced  = 0
$skipped = 0

Get-ChildItem -Path $ClientsDir -Directory | ForEach-Object {
    $clientName    = $_.Name
    $targetScripts = Join-Path $_.FullName "DNS Records\Scripts"
    $targetRoot    = Join-Path $_.FullName "DNS Records"

    if (Test-Path $targetScripts) {
        Write-Host "Syncing : $clientName"

        foreach ($ps1 in $ps1Files) {
            $dest   = Join-Path $targetScripts $ps1.Name
            $action = if (Test-Path $dest) { "Replaced" } else { "Added" }
            Copy-Item -Path $ps1.FullName -Destination $dest -Force
            Write-Host "  $action : $($ps1.Name)"
        }

        if (Test-Path $MasterBat) {
            $dest   = Join-Path $targetRoot "Run_DNS_Records.bat"
            $action = if (Test-Path $dest) { "Replaced" } else { "Added" }
            Copy-Item -Path $MasterBat -Destination $dest -Force
            Write-Host "  $action : Run_DNS_Records.bat"
        }

        $synced++
    } else {
        Write-Host "Skipped : $clientName (no DNS Records\Scripts folder)"
        $skipped++
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Done. Synced: $synced   Skipped: $skipped"
Write-Host "============================================================"
Write-Host ""
Write-Host "VERIFYING..."
Write-Host "------------------------------------------------------------"

$verified  = 0
$mismatch  = 0

Get-ChildItem -Path $ClientsDir -Directory | ForEach-Object {
    $targetScripts = Join-Path $_.FullName "DNS Records\Scripts"
    if (Test-Path $targetScripts) {
        foreach ($ps1 in $ps1Files) {
            $dest        = Join-Path $targetScripts $ps1.Name
            $srcHash     = (Get-FileHash $ps1.FullName -Algorithm MD5).Hash
            $destHash    = (Get-FileHash $dest -Algorithm MD5).Hash
            if ($srcHash -eq $destHash) {
                Write-Host "  OK       : $($_.Name) - $($ps1.Name)"
                $verified++
            } else {
                Write-Host "  MISMATCH : $($_.Name) - $($ps1.Name) *** NOT MATCHING ***"
                $mismatch++
            }
        }
    }
}

Write-Host "------------------------------------------------------------"
Write-Host " Verified: $verified   Mismatches: $mismatch"
Write-Host "============================================================"
