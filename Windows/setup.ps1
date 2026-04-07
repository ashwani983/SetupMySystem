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
$script:Errors = @()
$script:CommandLog = @()

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Type] $Message"
    Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Write-Section {
    param([string]$Title)
    $separator = "=" * 50
    Write-Host "`n$separator" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "$separator`n" -ForegroundColor Cyan
    Write-Log $Title "SECTION"
}

function Write-Command {
    param([string]$Command, [string]$Description)
    Write-Host "  > $Description" -ForegroundColor Yellow
    Write-Host "    CMD: $Command" -ForegroundColor DarkGray
    Write-Log "CMD: $Command | DESC: $Description" "COMMAND"
    $script:CommandLog += @{ Command = $Command; Description = $Description; Status = "PENDING" }
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
    Write-Log $Message "SUCCESS"
    $script:CommandLog[-1].Status = "SUCCESS"
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
    Write-Log $Message "WARNING"
    $script:CommandLog[-1].Status = "WARNING"
}

function Write-Error-Msg {
    param([string]$Message)
    Write-Host "  [X] $Message" -ForegroundColor Red
    Write-Log $Message "ERROR"
    $script:Errors += $Message
    $script:CommandLog[-1].Status = "ERROR"
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-InternetConnection {
    Write-Host "  Checking internet connection..." -NoNewline
    $cmd = "Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet"
    Write-Log "CMD: $cmd | DESC: Testing internet connectivity" "COMMAND"
    try {
        $result = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction Stop
        if ($result) {
            Write-Success "Connected"
            return $true
        }
    } catch { }
    Write-Warning "No internet connection detected"
    return $false
}

function Test-DiskSpace {
    param([int]$RequiredGB = 10)
    $drive = $env:SystemDrive
    $freeGB = [math]::Round((Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction SilentlyContinue).Free / 1GB, 2)
    Write-Host "  Checking disk space on ${drive}..." -NoNewline
    Write-Log "Disk space check: ${freeGB} GB free (required: ${RequiredGB} GB)" "INFO"
    if ($freeGB -ge $RequiredGB) {
        Write-Success "${freeGB} GB free - OK"
        return $true
    }
    Write-Warning "Low disk space (${freeGB} GB free, recommended: ${RequiredGB} GB)"
    return ($Force -or (Read-Host "Continue anyway? (y/n)") -eq 'y')
}

function Test-InstalledPackage {
    param([string]$PackageId)
    Write-Log "Checking if installed: $PackageId" "CHECK"
    $installed = winget list --id $PackageId -s winget --accept-source-agreements 2>$null | Select-String $PackageId
    return ($null -ne $installed)
}

function Backup-File {
    param([string]$Path)
    if (Test-Path $Path) {
        $backupPath = "$Path.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -Path $Path -Destination $backupPath -Force
        $script:ChangesMade += "Backup: $backupPath"
        Write-Log "Backed up $Path to $backupPath" "BACKUP"
        return $backupPath
    }
    return $null
}

function Invoke-Exec {
    param(
        [string]$Command,
        [string]$Description,
        [switch]$HideOutput,
        [switch]$IgnoreErrors
    )
    
    Write-Log "EXECUTING: $Command" "EXEC"
    Write-Log "DESC: $Description" "INFO"
    
    if ($DryRun) {
        Write-Host "    [DRY-RUN] Command skipped" -ForegroundColor Magenta
        Write-Log "DRY-RUN: $Command skipped" "INFO"
        return $true
    }
    
    try {
        if ($HideOutput) {
            $null = Invoke-Expression $Command 2>&1
        } else {
            $output = Invoke-Expression $Command 2>&1
            if ($output) {
                $output | ForEach-Object { Write-Log "  OUTPUT: $_" "OUTPUT" }
            }
        }
        
        if ($LASTEXITCODE -eq 0 -or $IgnoreErrors) {
            Write-Log "SUCCESS: Exit code 0" "RESULT"
            return $true
        } else {
            Write-Log "WARNING: Exit code $LASTEXITCODE" "WARN"
            return $false
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log "ERROR: $errorMsg" "ERROR"
        $script:Errors += "$Command : $errorMsg"
        if (-not $IgnoreErrors) {
            return $false
        }
    }
    return $true
}

function Install-Package {
    param([string]$PackageId, [string]$PackageName)
    
    if ($DryRun) {
        Write-Host "  [DRY-RUN] Would install: $PackageName" -ForegroundColor Magenta
        Write-Log "DRY-RUN: Would install $PackageName ($PackageId)" "INFO"
        return
    }
    
    if (Test-InstalledPackage -PackageId $PackageId) {
        Write-Success "$PackageName already installed, skipping"
        return
    }
    
    Write-Host "  Installing $PackageName..." -ForegroundColor White
    Write-Log "Installing: $PackageName ($PackageId)" "INSTALL"
    
    try {
        $process = Start-Process -FilePath "winget" -ArgumentList "install --id $PackageId --accept-package-agreements --accept-source-agreements --silent" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Success "$PackageName installed"
            $script:ChangesMade += "Installed: $PackageName"
        } else {
            Write-Warning "$PackageName installation failed or cancelled (exit code: $($process.ExitCode))"
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Warning "Error installing $PackageName: $errorMsg"
        $script:Errors += "Install $PackageName : $errorMsg"
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
    @{ Id = "Amazon.AWSCLIV2"; Name = "AWS CLI" },
    @{ Id = "Hashicorp.Terraform"; Name = "Terraform" },
    @{ Id = "Kubernetes.kubectl"; Name = "kubectl" },
    @{ Id = "Helm.Helm"; Name = "Helm" },
    @{ Id = "Flameshot.Flameshot"; Name = "Flameshot" }
)

Write-Section "Windows System Setup"
Write-Host "  Log file: $script:LogFile" -ForegroundColor DarkGray
if ($Verbose) { Write-Host "  Verbose mode enabled" -ForegroundColor DarkGray }
Write-Host ""
Write-Log "========================================" "INFO"
Write-Log "Starting Windows System Setup" "INFO"
Write-Log "Parameters: SkipVSCode=$SkipVSCode, SkipDocker=$SkipDocker, SkipDevOps=$SkipDevOps, DryRun=$DryRun, Force=$Force" "INFO"

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
Write-Log "Checking installed packages..." "INFO"
foreach ($pkg in $packages) {
    if (Test-InstalledPackage -PackageId $pkg.Id) {
        Write-Success "$($pkg.Name) already installed"
    }
}

Write-Section "Installing Software via winget"
foreach ($pkg in $packages) {
    if ($pkg.Id -eq "Microsoft.VisualStudioCode" -and $SkipVSCode) {
        Write-Warning "Skipping VS Code per request"
        Write-Log "SKIPPED: $($pkg.Name) per user request" "INFO"
        continue
    }
    Install-Package -PackageId $pkg.Id -PackageName $pkg.Name
}

if (-not $SkipDevOps) {
    Write-Section "Installing DevOps Tools"
    foreach ($pkg in $devopsPackages) {
        if ($pkg.Id -eq "Docker.DockerDesktop" -and $SkipDocker) {
            Write-Warning "Skipping Docker per request"
            Write-Log "SKIPPED: $($pkg.Name) per user request" "INFO"
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
        Write-Log "Creating PowerShell profile directory: $psProfileDir" "INFO"
        New-Item -ItemType Directory -Path $psProfileDir -Force | Out-Null
        Write-Success "Created profile directory"
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
            Write-Log "Appending PSReadLine config to: $psProfilePath" "INFO"
            Add-Content -Path $psProfilePath -Value $psReadLineConfig
            $script:ChangesMade += "PSReadLine: Config appended to $psProfilePath"
            Write-Success "PSReadLine configured"
        } else {
            Write-Success "PSReadLine already configured"
        }
    } else {
        Write-Log "Creating new profile with PSReadLine config: $psProfilePath" "INFO"
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
    $null = Invoke-Expression $cfg.cmd 2>$null
    Write-Log "Git config: $($cfg.desc)" "INFO"
}
Write-Success "Git configured"

if (-not $SkipDevOps) {
    Write-Section "Installing Bruno API Client"
    Write-Host "  Checking for Bruno..." -NoNewline
    if ((Get-Command bruno -ErrorAction SilentlyContinue) -or (Test-Path "$env:LOCALAPPDATA\Programs\Bruno\bruno.exe")) {
        Write-Success "Bruno already installed"
    } else {
        Write-Host "  Installing Bruno via npm..." -ForegroundColor White
        Write-Log "Installing Bruno via npm" "INSTALL"
        if ($DryRun) {
            Write-Host "    [DRY-RUN] Bruno installation skipped" -ForegroundColor Magenta
        } else {
            try {
                npm install -g bruno 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0 -or (Get-Command bruno -ErrorAction SilentlyContinue)) {
                    Write-Success "Bruno installed"
                    $script:ChangesMade += "Installed: Bruno"
                } else {
                    Write-Warning "Bruno installation may have failed. Verify with: npm list -g bruno"
                }
            } catch {
                Write-Warning "Bruno installation failed. Install manually: npm install -g bruno"
            }
        }
    }
    
    Write-Section "SSH Key Check"
    $sshKey = "$env:USERPROFILE\.ssh\id_ed25519.pub"
    Write-Host "  Checking for SSH key..." -NoNewline
    if (-not (Test-Path $sshKey)) {
        Write-Warning "No SSH key found. To generate one, run:"
        Write-Host "    ssh-keygen -t ed25519 -C `"your@email.com`"" -ForegroundColor Cyan
        Write-Log "SSH key not found - user notified" "INFO"
    } else {
        Write-Success "SSH key found at $sshKey"
    }
}

Write-Section "Setup Complete!"

$successCount = ($script:CommandLog | Where-Object { $_.Status -eq "SUCCESS" }).Count
$warnCount = ($script:CommandLog | Where-Object { $_.Status -eq "WARNING" }).Count
$errorCount = $script:Errors.Count

Write-Host "  Summary:" -ForegroundColor Cyan
Write-Host "    Commands executed: $($script:CommandLog.Count)" -ForegroundColor Gray
Write-Host "    Successful: $successCount" -ForegroundColor Green
Write-Host "    Warnings: $warnCount" -ForegroundColor Yellow
Write-Host "    Errors: $errorCount" -ForegroundColor Red

if ($script:ChangesMade.Count -gt 0) {
    Write-Host "`n  Changes made:" -ForegroundColor Cyan
    $script:ChangesMade | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
}

Write-Host "`n  Log saved to: $script:LogFile" -ForegroundColor DarkGray
Write-Host "  Restart PowerShell to apply PSReadLine changes." -ForegroundColor Green

Write-Log "========================================" "INFO"
Write-Log "Setup completed - Success: $successCount, Warnings: $warnCount, Errors: $errorCount" "SUMMARY"
Write-Log "========================================" "INFO"
