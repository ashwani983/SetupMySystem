#requires -RunAsAdministrator
param(
    [switch]$SkipVSCode,
    [switch]$SkipPSReadLine,
    [switch]$SkipDocker,
    [switch]$SkipDevOps,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$script:LogFile = "$env:TEMP\setup_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$script:ChangesMade = @()

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
    Write-Host $Message
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Log "=== $Title ==="
}

function Write-Success { param([string]$Message); Write-Host "  [OK] $Message" -ForegroundColor Green; Write-Log "SUCCESS: $Message" }
function Write-Warning { param([string]$Message); Write-Host "  [!] $Message" -ForegroundColor Yellow; Write-Log "WARN: $Message" }
function Write-Error-Msg { param([string]$Message); Write-Host "  [X] $Message" -ForegroundColor Red; Write-Log "ERROR: $Message" }

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-InternetConnection {
    Write-Host "Checking internet connection..." -NoNewline
    try {
        $result = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction Stop
        if ($result) { Write-Success "Connected"; return $true }
    } catch { }
    Write-Warning "No internet connection detected"
    return $false
}

function Test-DiskSpace {
    param([int]$RequiredGB = 10)
    $drive = $env:SystemDrive
    $freeGB = [math]::Round((Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction SilentlyContinue).Free / 1GB, 2)
    Write-Host "Disk space on ${drive}: ${freeGB} GB free" -NoNewline
    if ($freeGB -ge $RequiredGB) { Write-Success "OK"; return $true }
    Write-Warning "Low disk space (recommended: ${RequiredGB} GB)"
    return ($Force -or (Read-Host "Continue anyway? (y/n)") -eq 'y')
}

function Test-InstalledPackage {
    param([string]$PackageId)
    $installed = winget list --id $PackageId -s winget --accept-source-agreements 2>$null | Select-String $PackageId
    return ($null -ne $installed)
}

function Backup-File {
    param([string]$Path)
    if (Test-Path $Path) {
        $backupPath = "$Path.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -Path $Path -Destination $backupPath -Force
        $script:ChangesMade += "Backup: $backupPath"
        Write-Log "Backed up $Path to $backupPath"
        return $backupPath
    }
    return $null
}

function Set-EnvironmentVariable {
    param([string]$Name, [string]$Value, [string]$Scope = "User")
    $currentValue = [Environment]::GetEnvironmentVariable($Name, $Scope)
    if ($currentValue -ne $Value) {
        Backup-File "env:$Name"
        [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
        $script:ChangesMade += "EnvVar: $Name"
        Write-Log "Set $Name=$Value in $Scope scope"
    }
}

function New-SSHKey {
    $sshDir = "$env:USERPROFILE\.ssh"
    $sshKey = "$sshDir\id_ed25519"
    
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }
    
    if (-not (Test-Path "$sshKey.pub")) {
        Write-Host "Generating SSH key..." -NoNewline
        ssh-keygen -t ed25519 -C "automation@setup" -f $sshKey -N "" -q
        Write-Success "SSH key created at $sshKey.pub"
        Write-Host "`nYour public key:" -ForegroundColor Cyan
        Get-Content "$sshKey.pub"
    } else {
        Write-Success "SSH key already exists"
    }
}

function Install-Package {
    param([string]$PackageId, [string]$PackageName)
    
    if ($DryRun) {
        Write-Host "  [DRY-RUN] Would install: $PackageName" -ForegroundColor Magenta
        return
    }
    
    if (Test-InstalledPackage -PackageId $PackageId) {
        Write-Success "$PackageName already installed, skipping"
        return
    }
    
    Write-Host "  Installing $PackageName..." -NoNewline
    try {
        $output = winget install --id $PackageId --accept-package-agreements --accept-source-agreements --silent 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$PackageName installed"
        } else {
            Write-Warning "$PackageName installation failed or cancelled"
        }
    } catch {
        Write-Warning "Error installing $PackageName: $_"
    }
}

$packages = @(
    @{ Id = "Microsoft.VisualStudioCode"; Name = "VS Code" },
    @{ Id = "Git.Git"; Name = "Git" },
    @{ Id = "OpenJS.NodeJS.LTS"; Name = "Node.js LTS" },
    @{ Id = "GitHub.cli"; Name = "GitHub CLI" },
    @{ Id = "Python.Python.3.13"; Name = "Python 3.13" },
    @{ Id = "Oracle.JDK.21"; Name = "JDK 21" },
    @{ Id = "Google.FirebaseCLI"; Name = "Firebase CLI" },
    @{ Id = "Google.PlatformTools"; Name = "Android SDK" },
    @{ Id = "TheDocumentFoundation.LibreOffice"; Name = "LibreOffice" },
    @{ Id = "Ghisler.TotalCommander"; Name = "Total Commander" },
    @{ Id = "ApacheFriends.Xampp.8.2"; Name = "XAMPP" },
    @{ Id = "7zip.7zip"; Name = "7-Zip" },
    @{ Id = "Microsoft.WindowsTerminal"; Name = "Windows Terminal" }
)

$devopsPackages = @(
    @{ Id = "Docker.DockerDesktop"; Name = "Docker Desktop" },
    @{ Id = "Amazon.AWSCLI"; Name = "AWS CLI" },
    @{ Id = "Hashicorp.Terraform"; Name = "Terraform" },
    @{ Id = "Postman.Postman"; Name = "Postman" },
    @{ Id = "Kubernetes.kubectl"; Name = "kubectl" },
    @{ Id = "Helm.Helm"; Name = "Helm" },
    @{ Id = "Flameshot.Flameshot"; Name = "Flameshot" },
    @{ Id = "Brave.Brave"; Name = "Brave Browser" }
)

Write-Section "Windows System Setup"
Write-Host "Log file: $script:LogFile`n" -ForegroundColor DarkGray
Write-Log "Starting Windows System Setup"
Write-Log "Parameters: SkipVSCode=$SkipVSCode, SkipDocker=$SkipDocker, SkipDevOps=$SkipDevOps, DryRun=$DryRun, Force=$Force"

if (-not (Test-Administrator)) {
    Write-Error-Msg "Please run as Administrator!"
    exit 1
}

if (-not (Test-InternetConnection)) {
    if (-not $Force) {
        Write-Warning "Internet required for most installations"
        if ((Read-Host "Continue without internet? (y/n)") -ne 'y') { exit 1 }
    }
}

Test-DiskSpace -RequiredGB 15 | Out-Null

Write-Section "Checking Existing Installations"
foreach ($pkg in $packages) {
    if (Test-InstalledPackage -PackageId $pkg.Id) {
        Write-Success "$($pkg.Name) already installed"
    }
}

Write-Section "Installing Software via winget"
foreach ($pkg in $packages) {
    if ($pkg.Id -eq "Microsoft.VisualStudioCode" -and $SkipVSCode) {
        Write-Warning "Skipping VS Code per request"
        continue
    }
    Install-Package -PackageId $pkg.Id -PackageName $pkg.Name
}

if (-not $SkipDevOps) {
    Write-Section "Installing DevOps Tools"
    foreach ($pkg in $devopsPackages) {
        if ($pkg.Id -eq "Docker.DockerDesktop" -and $SkipDocker) {
            Write-Warning "Skipping Docker per request"
            continue
        }
        Install-Package -PackageId $pkg.Id -PackageName $pkg.Name
    }
}

if (-not $SkipPSReadLine) {
    Write-Section "Configuring PSReadLine"
    
    $psProfilePath = $PROFILE
    $psProfileDir = Split-Path $psProfilePath -Parent
    
    if (-not (Test-Path $psProfileDir)) {
        New-Item -ItemType Directory -Path $psProfileDir -Force | Out-Null
    }
    
    Backup-File -Path $psProfilePath
    
    $psReadLineConfig = @"

# PSReadLine Configuration
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -HistoryLimit 10000
    
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Ctrl+Space -Function Complete
    Set-PSReadLineKeyHandler -Key Escape -Function ClearScreen
    
    Set-PSReadLineOption -Colors @{
        Command = 'Cyan'
        Parameter = 'Gray'
        String = 'Green'
        Number = 'Yellow'
        Member = 'Magenta'
    }
}
"@

    if (Test-Path $psProfilePath) {
        $currentProfile = Get-Content $psProfilePath -Raw -ErrorAction SilentlyContinue
        if ($currentProfile -notmatch "PSReadLine") {
            Add-Content -Path $psProfilePath -Value $psReadLineConfig
            $script:ChangesMade += "PSReadLine: Config appended to $psProfilePath"
            Write-Success "PSReadLine configured"
        } else {
            Write-Success "PSReadLine already configured"
        }
    } else {
        Set-Content -Path $psProfilePath -Value $psReadLineConfig
        $script:ChangesMade += "PSReadLine: New profile created at $psProfilePath"
        Write-Success "PSReadLine configured (new profile created)"
    }
}

Write-Section "Configuring Git"
git config --global credential.helper wincred 2>$null
git config --global core.editor "code --wait" 2>$null
git config --global init.defaultBranch main 2>$null
Write-Success "Git configured"

if (-not $SkipDevOps) {
    Write-Section "SSH Key Setup"
    New-SSHKey
}

Write-Section "Setup Complete!"
Write-Host "Restart PowerShell to apply PSReadLine changes." -ForegroundColor Green
Write-Host "`nChanges made:" -ForegroundColor Cyan
$script:ChangesMade | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
Write-Host "`nLog saved to: $script:LogFile" -ForegroundColor DarkGray
Write-Log "Setup completed successfully"
