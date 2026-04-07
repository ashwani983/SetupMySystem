#requires -RunAsAdministrator
param(
    [switch]$SkipVSCode,
    [switch]$SkipPSReadLine,
    [switch]$SkipDocker,
    [switch]$SkipDevOps,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

$script:LogFile = "$env:TEMP\setup_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$script:ChangesMade = @()

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
    if ($script:Verbose) { Write-Host "  LOG: $Message" -ForegroundColor DarkGray }
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Log "=== $Title ==="
}

function Write-Command {
    param([string]$Command, [string]$Description)
    Write-Host "  > $Description" -ForegroundColor Yellow
    Write-Host "    $Command" -ForegroundColor DarkGray
    Write-Log "CMD: $Command"
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
    $cmd = "Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet"
    Write-Command $cmd "Testing internet connectivity"
    try {
        $result = Invoke-Expression $cmd -ErrorAction Stop
        if ($result) { Write-Success "Connected"; return $true }
    } catch { }
    Write-Warning "No internet connection detected"
    return $false
}

function Test-DiskSpace {
    param([int]$RequiredGB = 10)
    $drive = $env:SystemDrive
    $freeGB = [math]::Round((Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction SilentlyContinue).Free / 1GB, 2)
    Write-Host "Checking disk space on ${drive}..." -NoNewline
    $cmd = "Get-PSDrive -Name '$($drive.TrimEnd(':'))'"
    Write-Command $cmd "Getting disk space info"
    Write-Log "Disk space: ${freeGB} GB free (required: ${RequiredGB} GB)"
    if ($freeGB -ge $RequiredGB) { Write-Success "${freeGB} GB free - OK"; return $true }
    Write-Warning "Low disk space (${freeGB} GB free, recommended: ${RequiredGB} GB)"
    return ($Force -or (Read-Host "Continue anyway? (y/n)") -eq 'y')
}

function Test-InstalledPackage {
    param([string]$PackageId)
    $cmd = "winget list --id $PackageId -s winget --accept-source-agreements"
    Write-Command $cmd "Checking if $PackageId is installed"
    $installed = winget list --id $PackageId -s winget --accept-source-agreements 2>$null | Select-String $PackageId
    return ($null -ne $installed)
}

function Backup-File {
    param([string]$Path)
    if (Test-Path $Path) {
        $backupPath = "$Path.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $cmd = "Copy-Item -Path '$Path' -Destination '$backupPath' -Force"
        Write-Command $cmd "Backing up $Path"
        Copy-Item -Path $Path -Destination $backupPath -Force
        $script:ChangesMade += "Backup: $backupPath"
        Write-Log "Backed up $Path to $backupPath"
        return $backupPath
    }
    return $null
}

function Invoke-Exec {
    param([string]$Command, [string]$Description, [switch]$IgnoreErrors)
    
    Write-Command $Command $Description
    
    if ($DryRun) {
        Write-Host "    [DRY-RUN] Command skipped" -ForegroundColor Magenta
        Write-Log "DRY-RUN: $Command"
        return
    }
    
    try {
        Invoke-Expression $Command 2>&1 | Tee-Object -Append -FilePath $script:LogFile
        if ($LASTEXITCODE -eq 0 -or $IgnoreErrors) {
            Write-Log "SUCCESS: $Command"
        } else {
            Write-Warning "Command exited with code: $LASTEXITCODE"
        }
    } catch {
        $errorMsg = $_.Exception.Message
        if ($IgnoreErrors) {
            Write-Log "WARN: $Command - $errorMsg"
        } else {
            Write-Error-Msg "Failed: $errorMsg"
        }
    }
}

function Install-Package {
    param([string]$PackageId, [string]$PackageName)
    
    if ($DryRun) {
        Write-Host "  [DRY-RUN] Would install: $PackageName" -ForegroundColor Magenta
        Write-Log "DRY-RUN: Would install $PackageId"
        return
    }
    
    if (Test-InstalledPackage -PackageId $PackageId) {
        Write-Success "$PackageName already installed, skipping"
        return
    }
    
    Write-Host "  Installing $PackageName..." -ForegroundColor White
    $cmd = "winget install --id $PackageId --accept-package-agreements --accept-source-agreements --silent"
    Write-Command $cmd "Installing $PackageName via winget"
    
    try {
        $null = winget install --id $PackageId --accept-package-agreements --accept-source-agreements --silent 2>&1 | Tee-Object -Append -FilePath $script:LogFile
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$PackageName installed"
            $script:ChangesMade += "Installed: $PackageName"
        } else {
            Write-Warning "$PackageName installation failed or cancelled"
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Warning "Error installing $PackageName`: $errorMsg"
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
    @{ Id = "Kubernetes.kubectl"; Name = "kubectl" },
    @{ Id = "Helm.Helm"; Name = "Helm" },
    @{ Id = "Flameshot.Flameshot"; Name = "Flameshot" },
    @{ Id = "UseBruno.Bruno"; Name = "Bruno API Client" }
)

Write-Section "Windows System Setup"
Write-Host "Log file: $script:LogFile" -ForegroundColor DarkGray
if ($Verbose) { Write-Host "Verbose mode enabled" -ForegroundColor DarkGray }
Write-Host ""
Write-Log "Starting Windows System Setup"
Write-Log "Parameters: SkipVSCode=$SkipVSCode, SkipDocker=$SkipDocker, SkipDevOps=$SkipDevOps, DryRun=$DryRun, Force=$Force, Verbose=$Verbose"

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
Write-Host "  Running checks for all packages..."
foreach ($pkg in $packages) {
    Write-Log "Checking: $($pkg.Name)"
    if (Test-InstalledPackage -PackageId $pkg.Id) {
        Write-Success "$($pkg.Name) already installed"
    }
}

Write-Section "Installing Software via winget"
foreach ($pkg in $packages) {
    if ($pkg.Id -eq "Microsoft.VisualStudioCode" -and $SkipVSCode) {
        Write-Warning "Skipping VS Code per request"
        Write-Log "SKIPPED: $($pkg.Name) per user request"
        continue
    }
    Install-Package -PackageId $pkg.Id -PackageName $pkg.Name
}

if (-not $SkipDevOps) {
    Write-Section "Installing DevOps Tools"
    foreach ($pkg in $devopsPackages) {
        if ($pkg.Id -eq "Docker.DockerDesktop" -and $SkipDocker) {
            Write-Warning "Skipping Docker per request"
            Write-Log "SKIPPED: $($pkg.Name) per user request"
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
        $cmd = "New-Item -ItemType Directory -Path '$psProfileDir' -Force"
        Write-Command $cmd "Creating PowerShell profile directory"
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
            $cmd = "Add-Content -Path '$psProfilePath' -Value '<PSReadLineConfig>'"
            Write-Command $cmd "Appending PSReadLine config to profile"
            Add-Content -Path $psProfilePath -Value $psReadLineConfig
            $script:ChangesMade += "PSReadLine: Config appended to $psProfilePath"
            Write-Success "PSReadLine configured"
        } else {
            Write-Success "PSReadLine already configured"
        }
    } else {
        $cmd = "Set-Content -Path '$psProfilePath' -Value '<PSReadLineConfig>'"
        Write-Command $cmd "Creating new profile with PSReadLine config"
        Set-Content -Path $psProfilePath -Value $psReadLineConfig
        $script:ChangesMade += "PSReadLine: New profile created at $psProfilePath"
        Write-Success "PSReadLine configured (new profile created)"
    }
}

Write-Section "Configuring Git"
$gitConfigs = @(
    @{ cmd = "git config --global credential.helper wincred"; desc = "Setting credential helper" },
    @{ cmd = "git config --global core.editor `"code --wait`""; desc = "Setting default editor" },
    @{ cmd = "git config --global init.defaultBranch main"; desc = "Setting default branch" }
)
foreach ($cfg in $gitConfigs) {
    Write-Command $cfg.cmd $cfg.desc
    Invoke-Expression $cfg.cmd 2>$null
}
Write-Success "Git configured"

if (-not $SkipDevOps) {
    Write-Section "SSH Key Check"
    $sshKey = "$env:USERPROFILE\.ssh\id_ed25519.pub"
    $cmd = "Test-Path '$sshKey'"
    Write-Command $cmd "Checking for SSH key"
    if (-not (Test-Path $sshKey)) {
        Write-Warning "No SSH key found. To generate one, run:"
        Write-Host "  ssh-keygen -t ed25519 -C `"your@email.com`"" -ForegroundColor Cyan
        Write-Log "SSH key not found - user notified"
    } else {
        Write-Success "SSH key found at $sshKey"
    }
}

Write-Section "Setup Complete!"
Write-Host "Restart PowerShell to apply PSReadLine changes." -ForegroundColor Green
if ($script:ChangesMade.Count -gt 0) {
    Write-Host "`nChanges made:" -ForegroundColor Cyan
    $script:ChangesMade | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
}
Write-Host "`nLog saved to: $script:LogFile" -ForegroundColor DarkGray
Write-Log "Setup completed successfully"
