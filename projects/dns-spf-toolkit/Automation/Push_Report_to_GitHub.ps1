# ============================================================
# Push DNS Failure Report to GitHub
# Called automatically by Run_All_Reports.bat after each run
# Uses GitHub Contents API — no git install required on Windows
# ============================================================
# Token setup:
#   Create a file at %USERPROFILE%\github_token.txt
#   Paste your GitHub PAT into it (one line, no spaces)
# ============================================================

$TokenFile  = "$env:USERPROFILE\github_token.txt"
$RepoOwner  = "X1ndy02"
$RepoName   = "Home_Lab_1.0"
$Branch     = "main"

# Resolve paths relative to this script
$AutomationDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MasterDir     = Split-Path -Parent $AutomationDir
$ReportsDir    = Join-Path $MasterDir "Reports"
$LatestFile    = Join-Path $ReportsDir "DNS_Failure_Report_LATEST.txt"
$ReadmeFile    = Join-Path $MasterDir "README.txt"

# Files to push: local path -> GitHub repo path
$FilesToPush = @(
    @{ Local = $LatestFile; Remote = "projects/dns-spf-toolkit/Reports/DNS_Failure_Report_LATEST.txt" }
    @{ Local = $ReadmeFile; Remote = "projects/dns-spf-toolkit/README.txt" }
)

Write-Host ""
Write-Host "============================================================"
Write-Host " Pushing to GitHub"
Write-Host "============================================================"

if (-not (Test-Path -LiteralPath $TokenFile)) {
    Write-Host "ERROR: Token file not found at $TokenFile"
    Write-Host "       Create the file and paste your GitHub PAT into it."
    exit 1
}

$Token   = (Get-Content -LiteralPath $TokenFile -Raw).Trim()
$Headers = @{ Authorization = "Bearer $Token"; "User-Agent" = "dns-spf-toolkit" }

if (-not $Token) {
    Write-Host "ERROR: Token file is empty."
    exit 1
}

$Date      = Get-Date -Format "yyyy-MM-dd HH:mm"
$CommitMsg = "DNS monthly report $Date"
$AnyFailed = $false

function Push-FileToGitHub($LocalPath, $RemotePath) {
    if (-not (Test-Path -LiteralPath $LocalPath)) {
        Write-Host "  SKIP   : $RemotePath (file not found locally)"
        return
    }

    $Content = Get-Content -LiteralPath $LocalPath -Raw -Encoding UTF8
    $Encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Content))
    $ApiUrl  = "https://api.github.com/repos/$RepoOwner/$RepoName/contents/$RemotePath"

    $SHA = ""
    try {
        $existing = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers -Method GET -ErrorAction Stop
        $SHA = $existing.sha
    } catch {}

    $Body = @{ message = $CommitMsg; content = $Encoded; branch = $Branch }
    if ($SHA) { $Body.sha = $SHA }

    try {
        Invoke-RestMethod -Uri $ApiUrl -Headers $Headers -Method PUT `
            -Body ($Body | ConvertTo-Json -Depth 3) -ContentType "application/json" | Out-Null
        Write-Host "  Pushed : $RemotePath"
    } catch {
        Write-Host "  ERROR  : $RemotePath - $($_.Exception.Message)"
        $script:AnyFailed = $true
    }
}

foreach ($f in $FilesToPush) {
    Push-FileToGitHub $f.Local $f.Remote
}

Write-Host ""
if ($AnyFailed) {
    Write-Host " One or more files failed to push. Check errors above."
} else {
    Write-Host " All files pushed successfully."
    Write-Host " Report : https://github.com/$RepoOwner/$RepoName/blob/$Branch/projects/dns-spf-toolkit/Reports/DNS_Failure_Report_LATEST.txt"
}
Write-Host "============================================================"
