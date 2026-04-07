# SetupMySystem

Automated system setup scripts for fresh OS installations.

## Overview

This project contains scripts to quickly set up your development environment on:
- **Windows** (using winget + PowerShell)
- **Ubuntu/Linux** (using apt + shell)
- **macOS** (using Homebrew + shell)

## Features

### Permission Handling
- **Windows**: Prompts to restart as Administrator if not running with admin rights
- **Ubuntu/macOS**: Validates sudo access before proceeding

### Pre-flight Checks
- Internet connectivity verification
- Sudo/admin permission validation
- Disk space validation (requires minimum 15GB free)
- Existing installation detection (skips already installed packages)
- Config backup before modifications

### Safety Features
- Dry-run mode to preview changes without installing
- Automatic backup of existing configs (`~/.zshrc`, `$PROFILE`, etc.)
- Clean structured logging for easy troubleshooting
- Rollback-ready with backup timestamps

### Software Installed

| Software | Windows | Ubuntu | macOS |
|----------|---------|--------|-------|
| Visual Studio Code | winget | apt | Homebrew |
| Git | winget | apt | Homebrew |
| Node.js (LTS) | winget | apt | Homebrew |
| Python 3 | winget | apt | Homebrew |
| Java JDK 21 | winget | apt | Homebrew |
| Firebase CLI | winget | npm | npm |
| Android SDK Tools | winget | apt | Homebrew |
| LibreOffice | winget | apt | Homebrew |
| 7-Zip/p7zip | winget | apt | Homebrew |
| Windows Terminal | winget | - | - |
| GitHub CLI | winget | apt | Homebrew |
| Docker Desktop | winget | apt | Homebrew |
| AWS CLI | winget | official | Homebrew |
| Terraform | winget | apt | Homebrew |
| kubectl | winget | official | Homebrew |
| Helm | winget | official | Homebrew |
| Bruno API Client | npm | npm | npm |
| Flameshot | winget | - | - |
| Double Commander | winget | - | Homebrew |
| XAMPP | winget | - | Manual |

### Shell Enhancements

#### Windows (PSReadLine)
- History-based auto-suggestions
- Tab completion with menu
- Syntax highlighting for commands
- Arrow key history search
- 10,000 command history limit
- Ctrl+Space for completion
- Escape to clear screen

#### Linux & macOS (oh-my-zsh)
- **zsh-autosuggestions**: History-based suggestions
- **zsh-completions**: Tab auto-completion
- **zsh-syntax-highlighting**: Syntax highlighting
- **zsh-history-substring-search**: Arrow key history navigation
- **sudo**: Tab completion for sudo

### System Configuration

#### Windows
- Git credential helper (wincred)
- Git default editor (VS Code)
- Default branch (main)

#### Ubuntu/macOS
- Git credential helper (cache/osxkeychain)
- Git default editor (VS Code)
- Default branch (main)
- SSH key check (suggests generation if missing)
- Docker installation with user group setup (Linux)
- macOS preferences (show extensions, dock cleanup)

---

## Quick Start

### Windows

```powershell
# Run PowerShell as Administrator
.\Windows\setup.ps1
```

> **Note:** If not running as Administrator, the script will prompt to restart with admin rights.

Or use winget directly:
```powershell
winget import --file .\Windows\winget-install.json
```

### Ubuntu

```bash
chmod +x ubuntu/setup.sh
./ubuntu/setup.sh
```

> **Note:** Sudo access is required. The script will verify sudo privileges.

### macOS

```bash
chmod +x mac/setup.sh
./mac/setup.sh
```

> **Note:** Sudo access is required. The script will verify sudo privileges.

---

## Command Options

### Windows

```powershell
.\setup.ps1 -DryRun              # Preview without installing
.\setup.ps1 -Force               # Skip prompts
.\setup.ps1 -Verbose             # Show detailed logs
.\setup.ps1 -SkipVSCode          # Skip VS Code
.\setup.ps1 -SkipPSReadLine      # Skip PSReadLine config
.\setup.ps1 -SkipDocker          # Skip Docker
.\setup.ps1 -SkipDevOps          # Skip DevOps tools
```

### Ubuntu/macOS

```bash
./setup.sh --dry-run             # Preview without installing
./setup.sh --force               # Skip prompts
./setup.sh --verbose             # Show detailed output
./setup.sh --skip-zsh            # Skip oh-my-zsh
./setup.sh --skip-docker         # Skip Docker
./setup.sh --skip-devops         # Skip DevOps tools
./setup.sh --help                # Show help
```

---

## Post-Installation

### Windows
Restart PowerShell or run:
```powershell
. $PROFILE
```

### Ubuntu/macOS
Restart terminal or run:
```bash
exec zsh
```

### Configure Git
```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

### Add SSH Key to GitHub
```bash
ssh-keygen -t ed25519 -C "your@email.com"
cat ~/.ssh/id_ed25519.pub
# Copy output to GitHub > Settings > SSH Keys
```

---

## Manual Steps (Required)

### Windows
1. Configure Git after installation
2. Start Docker Desktop if installed

### Ubuntu
1. Download XAMPP from: https://www.apachefriends.org/download.html
2. Log out and back in for Docker group membership
3. Start Docker: `sudo systemctl start docker`

### macOS
1. Accept Xcode licenses: `sudo xcodebuild -license`
2. Start Docker Desktop from Applications

---

## Logging

All operations are logged to files for troubleshooting:

- **Windows**: `%TEMP%\setup_log_YYYYMMDD_HHMMSS.txt`
- **Ubuntu/macOS**: `/tmp/setup_log_YYYYMMDD_HHMMSS.txt`

### Log Format

```
[SECTION] Major section headers
[COMMAND] Command to be executed
[CHECK] Installation check result
[INSTALL] Package installation started
[RESULT] Success/failure result
[ERROR] Error occurred
[WARNING] Warning (non-fatal)
[BACKUP] File backup created
[SUMMARY] Final summary
```

### End of Run Summary

The script displays a summary at the end:
- Commands executed
- Errors encountered
- Changes made (installs, backups)

---

## Troubleshooting

### View Logs
- **Windows**: Check `%TEMP%\setup_log_*.txt`
- **Ubuntu/macOS**: Check `/tmp/setup_log_*.txt`

### Restore Backups
Backed up files are named with `.backup_YYYYMMDD_HHMMSS` suffix.

### Skip Already Installed
Scripts automatically detect installed packages and skip them.

### Common Issues

**Ubuntu: Bruno/kubectl/helm installation failed**
- Bruno is installed via npm: `npm install -g bruno`
- kubectl is installed from official Kubernetes repo
- Helm is installed from official Helm script

---

## Uninstallation

### Windows (winget)
```powershell
winget list  # Find package ID
winget uninstall --id <PackageID>
```

### Ubuntu
```bash
sudo apt remove <package-name>
sudo apt autoremove
```

### macOS
```bash
brew uninstall <package-name>
brew cleanup
```

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `--dry-run` first
5. Submit a pull request

---

## License

MIT License
