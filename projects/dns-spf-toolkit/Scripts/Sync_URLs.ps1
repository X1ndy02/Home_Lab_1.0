# ============================================================
# Sync Online Lookup shortcuts with config.txt
# Reads domain from ConfigFile, writes .url shortcuts to OutputDir\Online Lookup
# Adds missing, replaces existing, removes orphaned urls
# ============================================================

param(
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$OutputDir
)

if (-not (Test-Path $ConfigFile)) { Write-Host "Config not found: $ConfigFile"; return }
if (-not (Test-Path $OutputDir))  { Write-Host "Output dir not found: $OutputDir"; return }

$LookupDir = Join-Path $OutputDir "Online Lookup"

# Read domains from config.txt
$Domains = Get-Content $ConfigFile | Where-Object { $_ -match "^domain=" } | ForEach-Object { $_ -replace "^domain=", "" }

if (-not $Domains) {
    Write-Host "No domains found in $ConfigFile. Exiting."
    return
}

# Ensure Online Lookup folder exists
if (-not (Test-Path $LookupDir)) {
    New-Item -Path $LookupDir -ItemType Directory -Force | Out-Null
}

# Build expected url filenames from config
$expectedFiles = @()
foreach ($domain in $Domains) {
    $domainShort = $domain -replace '\.com\.au','' -replace '\.com','' -replace '\.au',''
    $urls = @{
        "DMARC" = "https://mxtoolbox.com/SuperTool.aspx?action=dmarc%3a$domain"
        "SPF"   = "https://mxtoolbox.com/SuperTool.aspx?action=spf%3a$domain"
        "DKIM"  = "https://mxtoolbox.com/SuperTool.aspx?action=dkim%3a$domain"
    }
    foreach ($key in $urls.Keys) {
        $fileName = "$($domainShort)_$key.url"
        $filePath = Join-Path $LookupDir $fileName
        $action   = if (Test-Path $filePath) { "Replaced" } else { "Added" }
        @("[InternetShortcut]", "URL=$($urls[$key])") | Out-File -FilePath $filePath -Encoding ASCII -Force
        Write-Host "  $action : $fileName"
        $expectedFiles += $fileName
    }
}

# Remove orphaned url files not in config
$existing = Get-ChildItem -Path $LookupDir -Filter "*.url"
foreach ($file in $existing) {
    if ($expectedFiles -notcontains $file.Name) {
        Remove-Item -Path $file.FullName -Force
        Write-Host "  Removed : $($file.Name) (domain no longer in config)"
    }
}
