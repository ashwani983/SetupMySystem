#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DARK='\033[0;90m'
NC='\033[0m'

LOG_FILE="/tmp/setup_log_$(date +%Y%m%d_%H%M%S).txt"
CHANGES_MADE=()
ERRORS=()
COMMAND_LOG=()
DRY_RUN=false
FORCE=false
VERBOSE=false
SKIP_ZSH=false
SKIP_DOCKER=false
SKIP_DEVOPS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|--check) DRY_RUN=true; echo -e "${YELLOW}Running in dry-run mode${NC}" ;;
        --force|-f) FORCE=true ;;
        --verbose|-v) VERBOSE=true ;;
        --skip-zsh) SKIP_ZSH=true ;;
        --skip-docker) SKIP_DOCKER=true ;;
        --skip-devops) SKIP_DEVOPS=true ;;
        --help|-h) echo "Usage: $0 [--dry-run] [--force] [--verbose] [--skip-zsh] [--skip-docker] [--skip-devops]"; exit 0 ;;
        *) shift ;;
    esac
done

log() {
    local type="${1:-INFO}"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$type] $message" | tee -a "$LOG_FILE"
}

section() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
    log "SECTION" "$1"
}

print_cmd() {
    local desc="$1"
    local cmd="$2"
    echo -e "${YELLOW}  > $desc${NC}"
    echo -e "${DARK}    CMD: $cmd${NC}"
    log "COMMAND" "CMD: $cmd | DESC: $desc"
    COMMAND_LOG+=("{\"command\": \"$cmd\", \"description\": \"$desc\", \"status\": \"PENDING\"}")
}

run_cmd() {
    local desc="$1"
    local cmd="$2"
    local ignore_errors="${3:-false}"
    
    print_cmd "$desc" "$cmd"
    log "EXEC" "EXECUTING: $cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "    ${MAGENTA}[DRY-RUN] Skipped${NC}"
        log "INFO" "DRY-RUN: $cmd skipped"
        return 0
    fi
    
    local output
    local exit_code=0
    
    output=$(eval "$cmd" 2>&1) || exit_code=$?
    
    if [[ -n "$output" && "$VERBOSE" == true ]]; then
        echo "$output" | while IFS= read -r line; do
            log "OUTPUT" "  $line"
        done
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log "RESULT" "SUCCESS: Exit code 0"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            log "WARN" "WARNING: Exit code $exit_code (ignored)"
            return 0
        else
            log "ERROR" "FAILED: Exit code $exit_code"
            ERRORS+=("$cmd : Exit code $exit_code")
            return 1
        fi
    fi
}

backup_file() {
    if [[ -f "$1" ]]; then
        local backup="${1}.backup_$(date +%Y%m%d_%H%M%S)"
        if [[ "$DRY_RUN" != true ]]; then
            cp "$1" "$backup"
            CHANGES_MADE+=("Backup: $backup")
            log "BACKUP" "Backed up $1 to $backup"
        fi
    fi
}

check_internet() {
    echo -e "${CYAN}  Checking internet connection...${NC}"
    if ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e "${GREEN}    [OK] Connected${NC}"
        log "CHECK" "Internet connection: OK"
        return 0
    else
        echo -e "${YELLOW}    [!] No internet connection detected${NC}"
        log "WARN" "Internet connection: FAILED"
        return 1
    fi
}

check_disk_space() {
    local required_gb=${1:-10}
    local free_gb
    free_gb=$(df -h / | awk 'NR==2 {print $4}' | sed 's/[A-Za-z]*//')
    echo -e "${CYAN}  Checking disk space...${NC}"
    log "INFO" "Disk space check: ${free_gb} GB free (required: ${required_gb} GB)"
    if [[ $free_gb -ge $required_gb ]]; then
        echo -e "${GREEN}    [OK] ${free_gb} GB free - OK${NC}"
        return 0
    else
        echo -e "${YELLOW}    [!] Low disk space (${free_gb} GB free, recommended: ${required_gb} GB)${NC}"
        log "WARN" "Low disk space: ${free_gb} GB"
        [[ "$FORCE" == true ]] || read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || [[ "$FORCE" == true ]] || exit 1
    fi
}

check_installed() {
    command -v "$1" &>/dev/null
}

install_brew() {
    local pkg="$1"
    local name="${2:-$pkg}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install: $name"
        log "INFO" "DRY-RUN: Would install $name via brew"
        return 0
    fi
    
    if brew list "$pkg" &>/dev/null; then
        echo -e "${GREEN}    [OK]${NC} $name already installed, skipping"
        log "CHECK" "$name already installed"
        return 0
    fi
    
    echo -e "${CYAN}  Installing $name...${NC}"
    log "INSTALL" "Installing $name ($pkg)"
    
    if brew install "$pkg" &>/dev/null; then
        echo -e "${GREEN}    [OK]${NC} $name installed"
        log "RESULT" "SUCCESS: $name installed"
        CHANGES_MADE+=("Installed: $name")
    else
        echo -e "${YELLOW}    [!]${NC} Failed to install $name"
        log "ERROR" "FAILED: $name installation"
        ERRORS+=("$name installation failed")
    fi
}

install_cask() {
    local pkg="$1"
    local name="${2:-$pkg}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install cask: $name"
        log "INFO" "DRY-RUN: Would install $name cask"
        return 0
    fi
    
    if brew list --cask "$pkg" &>/dev/null; then
        echo -e "${GREEN}    [OK]${NC} $name already installed, skipping"
        log "CHECK" "$name already installed"
        return 0
    fi
    
    echo -e "${CYAN}  Installing $name...${NC}"
    log "INSTALL" "Installing $name ($pkg)"
    
    if brew install --cask "$pkg" &>/dev/null; then
        echo -e "${GREEN}    [OK]${NC} $name installed"
        log "RESULT" "SUCCESS: $name installed"
        CHANGES_MADE+=("Installed: $name")
    else
        echo -e "${YELLOW}    [!]${NC} Failed to install $name (may need manual download)"
        log "ERROR" "FAILED: $name installation"
        ERRORS+=("$name installation failed")
    fi
}

section "macOS System Setup"
echo -e "  ${DARK}Log file: $LOG_FILE${NC}"
[[ "$VERBOSE" == true ]] && echo -e "  ${DARK}Verbose mode enabled${NC}"
echo ""
log "========================================" "INFO"
log "Starting macOS System Setup" "INFO"
log "Parameters: DRY_RUN=$DRY_RUN, FORCE=$FORCE, SKIP_ZSH=$SKIP_ZSH, SKIP_DOCKER=$SKIP_DOCKER, SKIP_DEVOPS=$SKIP_DEVOPS" "INFO"

if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}    [X]${NC} Do NOT run as root!"
    exit 1
fi

check_internet || { [[ "$FORCE" == true ]] || { echo -e "${YELLOW}    [!]${NC} Internet required, aborting"; exit 1; }; }
check_disk_space 15

section "Checking Existing Installations"
echo -e "  ${CYAN}Running checks for all packages...${NC}"
log "INFO" "Checking installed packages..."
for cmd in code git curl wget node npm python3 java brew docker terraform kubectl helm aws az minikube bruno; do
    if check_installed "$cmd"; then
        local path
        path=$(which "$cmd" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}    [OK]${NC} $cmd is installed ($path)"
        log "CHECK" "$cmd: installed at $path"
    else
        echo -e "  $cmd not found"
        log "CHECK" "$cmd: not found"
    fi
done

section "Checking for Homebrew"
if ! check_installed "brew"; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Homebrew"
        log "INFO" "DRY-RUN: Would install Homebrew"
    else
        echo -e "${CYAN}  Installing Homebrew...${NC}"
        log "INSTALL" "Installing Homebrew"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" &>/dev/null
        echo -e "${GREEN}    [OK]${NC} Homebrew installed"
        CHANGES_MADE+=("Installed: Homebrew")
        
        if [[ -f /opt/homebrew/bin/brew && -d "/opt/homebrew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            log "INFO" "Homebrew added to PATH"
        fi
    fi
else
    echo -e "${GREEN}    [OK]${NC} Homebrew already installed"
    if [[ "$DRY_RUN" == false ]]; then
        brew update &>/dev/null || true
    fi
fi

section "Installing Development Tools"
install_brew "git"
install_brew "curl"
install_brew "wget"
install_brew "node"
install_brew "python3"
install_brew "openjdk@21"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install npm packages: firebase-tools, azure-cli"
    log "INFO" "DRY-RUN: Would install npm global packages"
else
    if npm install -g firebase-tools &>/dev/null; then
        echo -e "${GREEN}    [OK]${NC} firebase-tools installed"
        log "RESULT" "SUCCESS: firebase-tools installed"
    fi
    npm install -g @azure/azure-cli &>/dev/null || true
fi

section "Installing Applications"
install_cask "visual-studio-code" "VS Code"
install_cask "libreoffice" "LibreOffice"
install_cask "double-commander" "Double Commander"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Bruno via npm"
else
    if ! command -v bruno &>/dev/null; then
        echo -e "${CYAN}  Installing Bruno via npm...${NC}"
        log "INSTALL" "Installing Bruno via npm"
        if npm install -g bruno &>/dev/null; then
            echo -e "${GREEN}    [OK]${NC} Bruno installed"
            CHANGES_MADE+=("Installed: Bruno")
        else
            echo -e "${YELLOW}    [!]${NC} Bruno installation failed. Run manually: npm install -g bruno"
        fi
    else
        echo -e "${GREEN}    [OK]${NC} Bruno already installed"
    fi
fi

section "Installing CLI Tools"
install_brew "p7zip"
install_brew "htop"
install_brew "jq"
install_brew "tree"
install_brew "vim"

if [[ "$SKIP_DEVOPS" == false ]]; then
    section "Installing DevOps Tools"
    install_cask "docker" "Docker Desktop"
    
    install_brew "terraform"
    install_brew "kubectl"
    install_brew "helm"
    install_brew "awscli"
    install_brew "azure-cli"
    install_brew "minikube"
fi

if [[ "$SKIP_ZSH" == false ]]; then
    section "Installing oh-my-zsh"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install oh-my-zsh and plugins"
        log "INFO" "DRY-RUN: Would install oh-my-zsh"
    else
        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            echo -e "${CYAN}  Installing oh-my-zsh...${NC}"
            log "INSTALL" "Installing oh-my-zsh"
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
            echo -e "${GREEN}    [OK]${NC} oh-my-zsh installed"
            CHANGES_MADE+=("Installed: oh-my-zsh")
        else
            echo -e "${GREEN}    [OK]${NC} oh-my-zsh already installed"
        fi
        
        backup_file "$HOME/.zshrc"
        
        local zsh_custom="$HOME/.oh-my-zsh/custom"
        mkdir -p "$zsh_custom/plugins"
        
        declare -A plugins
        plugins=(["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions" ["zsh-completions"]="https://github.com/zsh-users/zsh-completions" ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git" ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search.git")
        
        for plugin in "${!plugins[@]}"; do
            if [ ! -d "$zsh_custom/plugins/$plugin" ]; then
                echo -e "${CYAN}  Installing $plugin...${NC}"
                git clone "${plugins[$plugin]}" "$zsh_custom/plugins/$plugin" 2>/dev/null || true
                echo -e "${GREEN}    [OK]${NC} $plugin installed"
            fi
        done
        
        sed -i '' 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting sudo history-substring-search)/' ~/.zshrc 2>/dev/null || true
        echo -e "${GREEN}    [OK]${NC} Zsh plugins configured"
        CHANGES_MADE+=("Configured: Zsh plugins")
    fi
fi

section "Configuring Git"
backup_file "$HOME/.gitconfig"
git config --global credential.helper osxkeychain
git config --global core.editor "code --wait"
git config --global init.defaultBranch main
git config --global pull.rebase false
echo -e "${GREEN}    [OK]${NC} Git configured"
log "INFO" "Git configured"

if [[ "$SKIP_DEVOPS" == false ]]; then
    section "SSH Key Check"
    echo -e "  Checking for SSH key..." -NoNewline
    if [[ ! -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        echo -e "${YELLOW}    [!]${NC} No SSH key found. To generate one, run:"
        echo -e "      ${CYAN}ssh-keygen -t ed25519 -C \"your@email.com\"${NC}"
        log "INFO" "SSH key not found - user notified"
    else
        echo -e "${GREEN}    [OK]${NC} SSH key found"
    fi
fi

section "Configuring macOS"
if [[ "$DRY_RUN" == false ]]; then
    defaults write com.apple.dock persistent-apps -array 2>/dev/null || true
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true 2>/dev/null || true
    defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true 2>/dev/null || true
    killall Dock 2>/dev/null || true
    echo -e "${GREEN}    [OK]${NC} macOS configured"
    log "INFO" "macOS system preferences configured"
fi

if [[ "$DRY_RUN" == false ]]; then
    section "Cleaning Up"
    brew cleanup -q 2>/dev/null || true
    echo -e "${GREEN}    [OK]${NC} Cleanup complete"
    log "INFO" "Homebrew cleanup completed"
fi

section "Setup Complete!"

echo -e "  ${CYAN}Summary:${NC}"
echo -e "    Commands executed: ${#COMMAND_LOG[@]}"
echo -e "    Errors: ${#ERRORS[@]}"
echo -e "    Changes: ${#CHANGES_MADE[@]}"

if [[ ${#CHANGES_MADE[@]} -gt 0 ]]; then
    echo -e "\n  ${CYAN}Changes made:${NC}"
    for change in "${CHANGES_MADE[@]}"; do
        echo -e "    - $change"
    done
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo -e "\n  ${RED}Errors encountered:${NC}"
    for error in "${ERRORS[@]}"; do
        echo -e "    - $error"
    done
fi

echo -e "\n  ${DARK}Log saved to: $LOG_FILE${NC}"
echo -e "${GREEN}  Done! Run 'exec zsh' or restart terminal${NC}"

log "========================================" "INFO"
log "Setup completed - Commands: ${#COMMAND_LOG[@]}, Errors: ${#ERRORS[@]}, Changes: ${#CHANGES_MADE[@]}" "SUMMARY"
log "========================================" "INFO"

if [[ "$DRY_RUN" == false ]]; then
    section "Important Next Steps"
    echo -e "${YELLOW}1.${NC} Restart terminal or run: ${CYAN}exec zsh${NC}"
    echo -e "${YELLOW}2.${NC} Configure Git:"
    echo -e "   ${CYAN}git config --global user.name \"Your Name\"${NC}"
    echo -e "   ${CYAN}git config --global user.email \"your@email.com\"${NC}"
    if [[ "$SKIP_DEVOPS" == false ]]; then
        echo -e "${YELLOW}3.${NC} Generate SSH key (if not already done):"
        echo -e "   ${CYAN}ssh-keygen -t ed25519 -C \"your@email.com\"${NC}"
        echo -e "   ${CYAN}cat ~/.ssh/id_ed25519.pub${NC}"
        echo -e "   Copy output to GitHub > Settings > SSH Keys"
    fi
    if [[ "$SKIP_DOCKER" == false ]]; then
        echo -e "${YELLOW}4.${NC} Start Docker Desktop from Applications"
    fi
fi
