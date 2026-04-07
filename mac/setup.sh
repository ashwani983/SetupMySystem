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

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; log "INFO: $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; log "SUCCESS: $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; log "WARN: $1"; }
error() { echo -e "${RED}[X]${NC} $1"; log "ERROR: $1"; }
print_cmd() { echo -e "${YELLOW}  > $1${NC}"; echo -e "${DARK}    $2${NC}"; log "CMD: $2"; }
section() {
    echo -e "\n${CYAN}========================================"
    echo -e " $1"
    echo -e "========================================${NC}\n"
    log "=== $1 ==="
}

run_cmd() {
    local desc="$1"
    local cmd="$2"
    local ignore_errors="${3:-false}"
    
    print_cmd "$desc" "$cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "    ${MAGENTA}[DRY-RUN] Command skipped${NC}"
        log "DRY-RUN: $cmd"
        return 0
    fi
    
    if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS: $cmd"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            warn "Command failed (ignored): $cmd"
            log "WARN: $cmd - failed but continuing"
            return 0
        else
            error "Command failed: $cmd"
            return 1
        fi
    fi
}

backup_file() {
    if [[ -f "$1" ]]; then
        local backup="${1}.backup_$(date +%Y%m%d_%H%M%S)"
        print_cmd "Backing up $1" "cp $1 $backup"
        if [[ "$DRY_RUN" != true ]]; then
            cp "$1" "$backup"
            CHANGES_MADE+=("Backup: $backup")
            log "Backed up $1 to $backup"
        fi
    fi
}

check_internet() {
    info "Checking internet connection..."
    print_cmd "Pinging 8.8.8.8" "ping -c 1 8.8.8.8"
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
    local free_gb
    free_gb=$(df -h / | awk 'NR==2 {print $4}' | sed 's/[A-Za-z]*//')
    info "Checking disk space..."
    print_cmd "Free space: ${free_gb} GB" "df -h /"
    log "Disk space: ${free_gb} GB free (required: ${required_gb} GB)"
    if [[ $free_gb -ge $required_gb ]]; then
        success "${free_gb} GB free - OK"
        return 0
    else
        warn "Low disk space (${free_gb} GB free, recommended: ${required_gb} GB)"
        [[ "$FORCE" == true ]] || read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || [[ "$FORCE" == true ]] || exit 1
    fi
}

check_installed() {
    print_cmd "Checking $1" "command -v $1"
    command -v "$1" &>/dev/null
}

install_brew() {
    local pkg="$1"
    local name="${2:-$pkg}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install: $name"
        log "DRY-RUN: Would install $pkg via brew"
        return 0
    fi
    
    print_cmd "Checking if $name is installed" "brew list $pkg"
    if brew list "$pkg" &>/dev/null; then
        success "$name already installed, skipping"
        return 0
    fi
    
    info "Installing $name..."
    run_cmd "Installing $name" "brew install $pkg" || warn "Failed to install $name"
    success "$name installed"
    CHANGES_MADE+=("Installed: $name")
}

install_cask() {
    local pkg="$1"
    local name="${2:-$pkg}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install cask: $name"
        log "DRY-RUN: Would install $pkg cask"
        return 0
    fi
    
    print_cmd "Checking if $name is installed" "brew list --cask $pkg"
    if brew list --cask "$pkg" &>/dev/null; then
        success "$name already installed, skipping"
        return 0
    fi
    
    info "Installing $name..."
    run_cmd "Installing $name" "brew install --cask $pkg" || warn "Failed to install $name (may need manual download)"
    success "$name installed"
    CHANGES_MADE+=("Installed: $name")
}

section "macOS System Setup"
echo -e "Log file: $LOG_FILE"
[[ "$VERBOSE" == true ]] && echo -e "Verbose mode enabled"
echo ""
log "Starting macOS System Setup"
log "Parameters: DRY_RUN=$DRY_RUN, FORCE=$FORCE, VERBOSE=$VERBOSE, SKIP_ZSH=$SKIP_ZSH, SKIP_DOCKER=$SKIP_DOCKER, SKIP_DEVOPS=$SKIP_DEVOPS"

if [[ $EUID -eq 0 ]]; then
    error "Do NOT run as root!"
    exit 1
fi

check_internet || { [[ "$FORCE" == true ]] || { warn "Internet required, aborting"; exit 1; }; }
check_disk_space 15

section "Checking Existing Installations"
echo -e "  ${CYAN}Running checks for all packages...${NC}"
for cmd in code git curl wget node npm python3 java brew docker terraform kubectl helm aws az minikube; do
    log "Checking: $cmd"
    if check_installed "$cmd"; then
        local path
        path=$(which "$cmd" 2>/dev/null || echo "unknown")
        success "$cmd is installed ($path)"
    else
        info "$cmd not found"
    fi
done

section "Checking for Homebrew"
if ! check_installed "brew"; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Homebrew"
        log "DRY-RUN: Would install Homebrew"
    else
        info "Installing Homebrew..."
        run_cmd "Installing Homebrew" "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        success "Homebrew installed"
        CHANGES_MADE+=("Installed: Homebrew")
        
        if [[ -f /opt/homebrew/bin/brew && -d "/opt/homebrew" ]]; then
            run_cmd "Adding Homebrew to PATH" '(echo; echo '\''eval "$(/opt/homebrew/bin/brew shellenv)"'\'') >> ~/.zprofile'
            eval "$(/opt/homebrew/bin/brew shellenv)"
            info "Added Homebrew to PATH"
        fi
    fi
else
    success "Homebrew already installed"
    if [[ "$DRY_RUN" == false ]]; then
        run_cmd "Updating Homebrew" "brew update"
    fi
fi

section "Installing Development Tools"
install_brew "git"
install_brew "curl" "curl"
install_brew "wget" "wget"
install_brew "node"
install_brew "python3"
install_brew "openjdk@21"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install npm packages: firebase-tools, azure-cli"
    log "DRY-RUN: Would install npm global packages"
else
    run_cmd "Installing firebase-tools" "npm install -g firebase-tools"
    run_cmd "Installing azure-cli" "npm install -g @azure/azure-cli" || true
    success "Global npm packages installed"
fi

section "Installing Applications"
install_cask "visual-studio-code" "VS Code"
install_cask "libreoffice" "LibreOffice"
install_cask "double-commander" "Double Commander"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Bruno"
    log "DRY-RUN: Would install Bruno via npm"
else
    if ! command -v bruno &>/dev/null; then
        info "Installing Bruno..."
        run_cmd "Installing Bruno via npm" "npm install -g bruno"
        success "Bruno installed"
    else
        success "Bruno already installed"
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
        log "DRY-RUN: Would install oh-my-zsh"
    else
        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            info "Installing oh-my-zsh..."
            run_cmd "Installing oh-my-zsh" "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended"
            success "oh-my-zsh installed"
            CHANGES_MADE+=("Installed: oh-my-zsh")
        else
            success "oh-my-zsh already installed"
        fi
        
        backup_file "$HOME/.zshrc"
        
        local zsh_custom="$HOME/.oh-my-zsh/custom"
        run_cmd "Creating Zsh custom plugins directory" "mkdir -p $zsh_custom/plugins"
        
        declare -A plugins
        plugins=(["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions" ["zsh-completions"]="https://github.com/zsh-users/zsh-completions" ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git" ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search.git")
        
        for plugin in "${!plugins[@]}"; do
            if [ ! -d "$zsh_custom/plugins/$plugin" ]; then
                info "Installing $plugin..."
                run_cmd "Cloning $plugin" "git clone ${plugins[$plugin]} $zsh_custom/plugins/$plugin"
            fi
        done
        
        run_cmd "Updating Zsh plugins" "sed -i '' 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting sudo history-substring-search)/' ~/.zshrc"
        success "Zsh plugins configured"
        CHANGES_MADE+=("Configured: Zsh plugins")
    fi
fi

section "Configuring Git"
backup_file "$HOME/.gitconfig"
declare -A git_configs=(
    ["credential.helper"]="osxkeychain"
    ["core.editor"]="code --wait"
    ["init.defaultBranch"]="main"
    ["pull.rebase"]="false"
)
for key in "${!git_configs[@]}"; do
    run_cmd "Setting git $key" "git config --global $key \"${git_configs[$key]}\""
done
success "Git configured"

if [[ "$SKIP_DEVOPS" == false ]]; then
    section "SSH Key Check"
    print_cmd "Checking SSH key" "test -f $HOME/.ssh/id_ed25519.pub"
    if [[ ! -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        warn "No SSH key found. To generate one, run:"
        echo -e "  ${CYAN}ssh-keygen -t ed25519 -C \"your@email.com\"${NC}"
        log "SSH key not found - user notified"
    else
        success "SSH key found"
    fi
fi

section "Configuring macOS"
if [[ "$DRY_RUN" == false ]]; then
    run_cmd "Hiding dock icons for unused apps" 'defaults write com.apple.dock persistent-apps -array'
    run_cmd "Showing all file extensions" 'defaults write NSGlobalDomain AppleShowAllExtensions -bool true'
    run_cmd "Disabling automatic termination" 'defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true'
    run_cmd "Restarting Dock" 'killall Dock 2>/dev/null || true'
    success "macOS configured"
fi

if [[ "$DRY_RUN" == false ]]; then
    section "Cleaning Up"
    run_cmd "Running Homebrew cleanup" "brew cleanup -q" || true
    success "Cleanup complete"
fi

section "Setup Complete!"
echo -e "${GREEN}Done! Run 'exec zsh' or restart terminal${NC}"
if [[ ${#CHANGES_MADE[@]} -gt 0 ]]; then
    echo -e "\n${CYAN}Changes made:${NC}"
    for change in "${CHANGES_MADE[@]}"; do
        echo -e "  ${YELLOW}-${NC} $change"
    done
fi
echo -e "\n${CYAN}Log saved to:${NC} $LOG_FILE"
log "Setup completed successfully"

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
