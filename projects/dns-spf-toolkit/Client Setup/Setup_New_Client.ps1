# ============================================================
# Setup New Client
# Called by Setup_New_Client.bat dropped into a new client folder
# Builds DNS Records folder inside ClientPath
# Supports multiple domains
# ============================================================

param(
    [Parameter(Mandatory=$true)][string]$ClientPath
)

$MasterDir = "\\YOUR-SERVER\shared\!Client Infrastructure Information\YOUR-MASTER-CLIENT\DNS Records\DNS Sync Folder\Scripts"

Write-Host "============================================================"
Write-Host " Setup New Client"
Write-Host "============================================================"
Write-Host "Client folder : $ClientPath"
Write-Host ""

# Ask for domains - one per line, blank line ends input
Write-Host "Enter client domain(s). Press Enter on a blank line to finish."
Write-Host ""

$domains = @()
$counter = 1
while ($true) {
    $entry = Read-Host "Domain $counter"
    if (-not $entry) { break }
    $domains += $entry.Trim()
    $counter++
}

if ($domains.Count -eq 0) {
    Write-Host "No domains entered. Exiting."
    exit
}

# Build folder structure
$dnsRecords = Join-Path $ClientPath "DNS Records"
$lookupDir  = Join-Path $dnsRecords "Online Lookup"

if (-not (Test-Path -LiteralPath $dnsRecords)) { New-Item -Path $dnsRecords -ItemType Directory -Force | Out-Null }
if (-not (Test-Path -LiteralPath $lookupDir))  { New-Item -Path $lookupDir  -ItemType Directory -Force | Out-Null }

Write-Host ""
Write-Host "Created : DNS Records\"
Write-Host "Created : DNS Records\Online Lookup\"

# Create config.txt with all domains
$configFile = Join-Path $dnsRecords "config.txt"
$configLines = $domains | ForEach-Object { "domain=$_" }
$configLines | Out-File -FilePath $configFile -Encoding ASCII -Force
Write-Host "Created : config.txt"
foreach ($d in $domains) {
    Write-Host "          domain=$d"
}

# Copy !Run_DNS_Records.bat from master
$batSource = Join-Path $MasterDir "!Run_DNS_Records.bat"
$batDest   = Join-Path $dnsRecords "!Run_DNS_Records.bat"

if (Test-Path -LiteralPath $batSource) {
    Copy-Item -LiteralPath $batSource -Destination $batDest -Force
    Write-Host "Copied  : !Run_DNS_Records.bat from master"
} else {
    Write-Host "WARN    : Master bat not found at $batSource"
}

# Generate Online Lookup .url shortcuts via master script
$urlScript = Join-Path $MasterDir "Sync_URLs.ps1"
if (Test-Path -LiteralPath $urlScript) {
    & $urlScript -ConfigFile $configFile -OutputDir $dnsRecords
} else {
    Write-Host "WARN    : Sync_URLs.ps1 not found at $urlScript"
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Done. Client is set up."
Write-Host "============================================================"
