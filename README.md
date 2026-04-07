# SetupMySystem

Automated system setup scripts for fresh OS installations.

## Overview

This project contains scripts to quickly set up your development environment on:
- **Windows** (using winget + PowerShell)
- **Ubuntu/Linux** (using apt + shell)
- **macOS** (using Homebrew + shell)

## Software Installed

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
| 7-Zip | winget | apt | Homebrew |
| XAMPP | winget | apt | Homebrew |
| Total Commander | winget | - | Homebrew |
| Windows Terminal | winget | - | - |
| GitHub CLI | winget | apt | Homebrew |

## Features

### Windows
- **PSReadLine** configured with:
  - History-based auto-suggestions
  - Tab completion
  - Syntax highlighting
  - Arrow key history search

### Linux & macOS
- **oh-my-zsh** with:
  - **zsh-autosuggestions**: History-based suggestions
  - **zsh-completions**: Tab auto-completion
  - **zsh-syntax-highlighting**: Syntax highlighting

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

## Options

### Windows
```powershell
.\setup.ps1 -SkipVSCode    # Skip VS Code installation
.\setup.ps1 -SkipPSReadLine # Skip PSReadLine configuration
```

### Ubuntu/macOS
```bash
./setup.sh --skip-zsh  # Skip oh-my-zsh installation
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

---

## Manual Steps (Required)

### Windows
1. Configure Git after installation:
   ```powershell
   git config --global user.name "Your Name"
   git config --global user.email "your@email.com"
   ```

### Ubuntu
1. Download XAMPP from: https://www.apachefriends.org/download.html
2. Set up Java environment variables if needed

### macOS
1. Accept Xcode licenses: `sudo xcodebuild -license`
2. Set up Android SDK environment variables if needed

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
4. Submit a pull request

---

## License

MIT License
