#requires -RunAsAdministrator
param(
    [switch]$SkipVSCode,
    [switch]$SkipPSReadLine
)

$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Section "Windows System Setup"

if (-not (Test-Administrator)) {
    Write-Host "Please run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "Starting Windows System Setup..." -ForegroundColor Green
Write-Host ""

$packages = @(
    "Microsoft.VisualStudioCode",
    "Git.Git",
    "OpenJS.NodeJS.LTS",
    "GitHub.cli",
    "Python.Python.3.13",
    "Oracle.JDK.21",
    "Google.FirebaseCLI",
    "Google.PlatformTools",
    "TheDocumentFoundation.LibreOffice",
    "Ghisler.TotalCommander",
    "ApacheFriends.Xampp.8.2",
    "7zip.7zip",
    "Microsoft.WindowsTerminal"
)

Write-Section "Installing Software via winget"

foreach ($package in $packages) {
    $packageName = $package.Split('.')[-1]
    
    if ($package -eq "Microsoft.VisualStudioCode" -and $SkipVSCode) {
        Write-Host "Skipping VS Code..." -ForegroundColor Yellow
        continue
    }
    
    Write-Host "Installing $packageName..." -ForegroundColor Cyan
    winget install --id $package --accept-package-agreements --accept-source-agreements --silent 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  $packageName installed!" -ForegroundColor Green
    } else {
        Write-Host "  $packageName may already be installed or skipped" -ForegroundColor Yellow
    }
}

if (-not $SkipPSReadLine) {
    Write-Section "Configuring PSReadLine"
    
    $psProfilePath = $PROFILE
    $psProfileDir = Split-Path $psProfilePath -Parent
    
    if (-not (Test-Path $psProfileDir)) {
        New-Item -ItemType Directory -Path $psProfileDir -Force | Out-Null
    }
    
    $psReadLineConfig = @"

# PSReadLine Configuration
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    
    Set-PSReadLineOption -Colors @{
        Command = 'Cyan'
        Parameter = 'Gray'
        String = 'Green'
        Number = 'Yellow'
    }
}
"@

    if (Test-Path $psProfilePath) {
        $currentProfile = Get-Content $psProfilePath -Raw -ErrorAction SilentlyContinue
        if ($currentProfile -notmatch "PSReadLine") {
            Add-Content -Path $psProfilePath -Value $psReadLineConfig
        }
    } else {
        Set-Content -Path $psProfilePath -Value $psReadLineConfig
    }
    
    Write-Host "PSReadLine configured!" -ForegroundColor Green
}

Write-Section "Setup Complete!"
Write-Host "Restart PowerShell to apply PSReadLine changes." -ForegroundColor Green
