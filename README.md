# SetupMySystem

Automated system setup scripts for fresh OS installations.

## Overview

This project contains scripts to quickly set up your development environment on:
- **Windows** (using winget + PowerShell)
- **Ubuntu/Linux** (using apt + shell)
- **macOS** (using Homebrew + shell)

## Features

### Pre-flight Checks
- Internet connectivity verification
- Disk space validation (requires minimum 15GB free)
- Existing installation detection (skips already installed packages)
- Config backup before modifications

### Safety Features
- Dry-run mode to preview changes without installing
- Automatic backup of existing configs (`~/.zshrc`, `$PROFILE`, etc.)
- Log file generation for troubleshooting
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
| AWS CLI | winget | apt | Homebrew |
| Terraform | winget | apt | Homebrew |
| kubectl | winget | apt | Homebrew |
| Helm | winget | apt | Homebrew |
| Postman | winget | - | Homebrew |
| Brave Browser | winget | - | Homebrew |
| Double Commander | winget | - | Homebrew |
| XAMPP | winget | apt | Manual |

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
- SSH key generation (ED25519)
- Docker installation with user group setup (Linux)

---

## Quick Start

### Windows

```powershell
# Run PowerShell as Administrator
.\Windows\setup.ps1
```

Or use winget directly:
```powershell
winget import --file .\Windows\winget-install.json
```

### Ubuntu

```bash
chmod +x ubuntu/setup.sh
./ubuntu/setup.sh
```

### macOS

```bash
chmod +x mac/setup.sh
./mac/setup.sh
```

---

## Command Options

### Windows

```powershell
.\setup.ps1 -DryRun              # Preview without installing
.\setup.ps1 -Force               # Skip prompts
.\setup.ps1 -SkipVSCode          # Skip VS Code
.\setup.ps1 -SkipPSReadLine      # Skip PSReadLine config
.\setup.ps1 -SkipDocker          # Skip Docker
.\setup.ps1 -SkipDevOps          # Skip DevOps tools
```

### Ubuntu/macOS

```bash
./setup.sh --dry-run             # Preview without installing
./setup.sh --force               # Skip prompts
./setup.sh --skip-zsh            # Skip oh-my-zsh
./setup.sh --skip-docker         # Skip Docker
./setup.sh --skip-devops         # Skip DevOps tools
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

## Troubleshooting

### View Logs
- **Windows**: Check `%TEMP%\setup_log_*.txt`
- **Ubuntu/macOS**: Check `/tmp/setup_log_*.txt`

### Restore Backups
Backed up files are named with `.backup_YYYYMMDD_HHMMSS` suffix.

### Skip Already Installed
Scripts automatically detect installed packages and skip them.

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
