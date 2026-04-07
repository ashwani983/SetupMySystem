#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="/tmp/setup_log_$(date +%Y%m%d_%H%M%S).txt"
CHANGES_MADE=()
DRY_RUN=false
FORCE=false
SKIP_ZSH=false
SKIP_DOCKER=false
SKIP_DEVOPS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|--check) DRY_RUN=true; echo -e "${YELLOW}Running in dry-run mode${NC}" ;;
        --force|-f) FORCE=true ;;
        --skip-zsh) SKIP_ZSH=true ;;
        --skip-docker) SKIP_DOCKER=true ;;
        --skip-devops) SKIP_DEVOPS=true ;;
        --help|-h) echo "Usage: $0 [--dry-run] [--force] [--skip-zsh] [--skip-docker] [--skip-devops]"; exit 0 ;;
        *) shift ;;
    esac
done

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; log "INFO: $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; log "SUCCESS: $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; log "WARN: $1"; }
error() { echo -e "${RED}[X]${NC} $1"; log "ERROR: $1"; }
section() {
    echo -e "\n${CYAN}========================================"
    echo -e " $1"
    echo -e "========================================${NC}\n"
    log "=== $1 ==="
}

backup_file() {
    if [[ -f "$1" ]]; then
        local backup="${1}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$1" "$backup"
        CHANGES_MADE+=("Backup: $backup")
        log "Backed up $1 to $backup"
    fi
}

check_internet() {
    info "Checking internet connection..."
    if ping -c 1 8.8.8.8 &>/dev/null; then
        success "Connected"
        return 0
    else
        warn "No internet connection detected"
        return 1
    fi
}

check_disk_space() {
    local required_gb=${1:-10}
    local free_gb=$(df -g / | awk 'NR==2 {print $4}')
    info "Disk space: ${free_gb} GB free"
    if [[ $free_gb -ge $required_gb ]]; then
        success "Disk space OK"
        return 0
    else
        warn "Low disk space (recommended: ${required_gb} GB)"
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
        echo -e "${MAGENTA}[DRY-RUN]${NC} Would install: $name"
        return 0
    fi
    
    if brew list "$pkg" &>/dev/null; then
        success "$name already installed, skipping"
        return 0
    fi
    
    info "Installing $name..."
    if brew install "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
        success "$name installed"
        CHANGES_MADE+=("Installed: $name")
    else
        warn "Failed to install $name"
    fi
}

install_cask() {
    local pkg="$1"
    local name="${2:-$pkg}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${NC} Would install cask: $name"
        return 0
    fi
    
    if brew list --cask "$pkg" &>/dev/null; then
        success "$name already installed, skipping"
        return 0
    fi
    
    info "Installing $name..."
    if brew install --cask "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
        success "$name installed"
        CHANGES_MADE+=("Installed: $name")
    else
        warn "Failed to install $name (may need manual download)"
    fi
}

section "macOS System Setup"
echo -e "Log file: $LOG_FILE\n"
log "Starting macOS System Setup"
log "Parameters: DRY_RUN=$DRY_RUN, FORCE=$FORCE, SKIP_ZSH=$SKIP_ZSH, SKIP_DOCKER=$SKIP_DOCKER, SKIP_DEVOPS=$SKIP_DEVOPS"

if [[ $EUID -eq 0 ]]; then
    error "Do NOT run as root!"
    exit 1
fi

check_internet || { [[ "$FORCE" == true ]] || { warn "Internet required, aborting"; exit 1; }; }
check_disk_space 15

section "Checking Existing Installations"
for cmd in code git curl wget node npm python3 java brew; do
    if check_installed "$cmd"; then
        success "$cmd is installed ($(which $cmd))"
    else
        info "$cmd not found"
    fi
done

section "Checking for Homebrew"
if ! check_installed "brew"; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${NC} Would install Homebrew"
    else
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        success "Homebrew installed"
        CHANGES_MADE+=("Installed: Homebrew")
        
        if [[ -f /opt/homebrew/bin/brew && -d "/opt/homebrew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            info "Added Homebrew to PATH"
        fi
    fi
else
    success "Homebrew already installed"
    if [[ "$DRY_RUN" == false ]]; then
        brew update 2>&1 | tee -a "$LOG_FILE" || true
    fi
fi

section "Installing Development Tools"
install_brew "git"
install_brew "curl" "curl"
install_brew "wget" "wget"
install_brew "node"
install_brew "python3"
install_brew "openjdk@21"

if [[ "$DRY_RUN" == false ]]; then
    info "Installing global npm packages..."
    npm install -g firebase-tools 2>&1 | tee -a "$LOG_FILE" || warn "Failed to install firebase-tools"
    npm install -g @azure/azure-cli 2>&1 | tee -a "$LOG_FILE" || true
fi

section "Installing Applications"
install_cask "visual-studio-code" "VS Code"
install_cask "libreoffice" "LibreOffice"
install_cask "double-commander" "Double Commander"
install_cask "bruno" "Bruno API Client"

install_brew "p7zip"
install_brew "htop" "htop"
install_brew "jq"
install_brew "tree"
install_brew "vim"
install_brew "macvim" "MacVim"

section "Installing DevOps Tools"
if [[ "$SKIP_DEVOPS" == false ]]; then
    install_cask "docker" "Docker Desktop"
    
    install_brew "terraform"
    install_brew "kubectl"
    install_brew "helm"
    install_brew "awscli"
    install_brew "azure-cli"
    install_brew "minikube"
    
    install_brew "cloudflare-cloudflare-warp" "Cloudflare WARP"
fi

if [[ "$SKIP_ZSH" == false ]]; then
    section "Installing oh-my-zsh"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${NC} Would install oh-my-zsh and plugins"
    else
        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            info "Installing oh-my-zsh..."
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
            success "oh-my-zsh installed"
            CHANGES_MADE+=("Installed: oh-my-zsh")
        else
            success "oh-my-zsh already installed"
        fi
        
        backup_file "$HOME/.zshrc"
        
        ZSH_CUSTOM="${HOME}/.oh-my-zsh/custom"
        mkdir -p "$ZSH_CUSTOM/plugins"
        
        declare -A plugins=(
            ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
            ["zsh-completions"]="https://github.com/zsh-users/zsh-completions"
            ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
            ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search.git"
        )
        
        for plugin in "${!plugins[@]}"; do
            if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
                info "Installing $plugin..."
                git clone "${plugins[$plugin]}" "$ZSH_CUSTOM/plugins/$plugin" 2>/dev/null || true
            fi
        done
        
        sed -i '' 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting sudo history-substring-search)/' ~/.zshrc 2>/dev/null || true
        success "Zsh plugins configured"
        CHANGES_MADE+=("Configured: Zsh plugins")
    fi
fi

section "Configuring Git"
backup_file "$HOME/.gitconfig"
git config --global credential.helper osxkeychain
git config --global core.editor "code --wait"
git config --global init.defaultBranch main
git config --global pull.rebase false
success "Git configured"

if [[ "$SKIP_DEVOPS" == false ]]; then
    section "SSH Key Check"
    if [[ ! -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        warn "No SSH key found. To generate one, run:"
        echo -e "  ${CYAN}ssh-keygen -t ed25519 -C \"your@email.com\"${NC}"
    else
        success "SSH key found"
    fi
fi

section "Configuring macOS"
if [[ "$DRY_RUN" == false ]]; then
    info "Hiding dock icons for unused apps..."
    defaults write com.apple.dock persistent-apps -array
    killall Dock 2>/dev/null || true
    
    info "Showing all file extensions..."
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    
    info "Disabling automatic termination..."
    defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true
    
    success "macOS configured"
fi

if [[ "$DRY_RUN" == false ]]; then
    section "Cleaning Up"
    brew cleanup -q 2>&1 | tee -a "$LOG_FILE" || true
    success "Cleanup complete"
fi

section "Setup Complete!"
echo -e "${GREEN}Done! Run 'exec zsh' or restart terminal${NC}"
echo -e "\n${CYAN}Changes made:${NC}"
for change in "${CHANGES_MADE[@]}"; do
    echo -e "  ${YELLOW}-${NC} $change"
done
echo -e "\n${CYAN}Log saved to:${NC} $LOG_FILE"
log "Setup completed successfully"

if [[ "$DRY_RUN" == false ]]; then
    section "Important Next Steps"
    echo -e "${YELLOW}1.${NC} Restart terminal or run: ${CYAN}exec zsh${NC}"
    echo -e "${YELLOW}2.${NC} Configure Git:"
    echo -e "   ${CYAN}git config --global user.name \"Your Name\"${NC}"
    echo -e "   ${CYAN}git config --global user.email \"your@email.com\"${NC}"
    if [[ "$SKIP_DEVOPS" == false ]]; then
        echo -e "${YELLOW}3.${NC} Add SSH key to GitHub:"
        echo -e "   ${CYAN}cat ~/.ssh/id_ed25519.pub${NC}"
        echo -e "   Copy output to GitHub > Settings > SSH Keys"
    fi
    if [[ "$SKIP_DOCKER" == false ]]; then
        echo -e "${YELLOW}4.${NC} Start Docker Desktop application"
    fi
fi
