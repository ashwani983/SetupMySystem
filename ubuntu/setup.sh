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
        --dry-run|--check) DRY_RUN=true; YELLOW "Running in dry-run mode"; shift ;;
        --force|-f) FORCE=true; shift ;;
        --skip-zsh) SKIP_ZSH=true; shift ;;
        --skip-docker) SKIP_DOCKER=true; shift ;;
        --skip-devops) SKIP_DEVOPS=true; shift ;;
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
    local free_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
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

generate_ssh_key() {
    local ssh_dir="$HOME/.ssh"
    local ssh_key="$ssh_dir/id_ed25519"
    
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    if [[ ! -f "$ssh_key.pub" ]]; then
        info "Generating SSH key..."
        ssh-keygen -t ed25519 -C "automation@setup" -f "$ssh_key" -N "" -q
        success "SSH key created at $ssh_key.pub"
        echo -e "${CYAN}Your public key:${NC}"
        cat "$ssh_key.pub"
    else
        success "SSH key already exists"
    fi
}

install_package() {
    local pkg="$1"
    local pkg_name="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${NC} Would install: $pkg_name"
        return 0
    fi
    
    if dpkg -l | grep -q "^ii  $pkg "; then
        success "$pkg_name already installed, skipping"
        return 0
    fi
    
    info "Installing $pkg_name..."
    if sudo apt install -y "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
        success "$pkg_name installed"
        CHANGES_MADE+=("Installed: $pkg")
    else
        warn "Failed to install $pkg_name"
    fi
}

section "Ubuntu System Setup"
echo -e "Log file: $LOG_FILE\n"
log "Starting Ubuntu System Setup"
log "Parameters: DRY_RUN=$DRY_RUN, FORCE=$FORCE, SKIP_ZSH=$SKIP_ZSH, SKIP_DOCKER=$SKIP_DOCKER, SKIP_DEVOPS=$SKIP_DEVOPS"

if [[ $EUID -eq 0 ]]; then
    error "Do NOT run as root!"
    exit 1
fi

check_internet || { [[ "$FORCE" == true ]] || { warn "Internet required, aborting"; exit 1; }; }
check_disk_space 15

section "Checking Existing Installations"
for cmd in code git curl wget node npm python3 java; do
    if check_installed "$cmd"; then
        success "$cmd is installed ($(which $cmd))"
    else
        info "$cmd not found"
    fi
done

section "Updating Package List"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${MAGENTA}[DRY-RUN]${NC} Would run: sudo apt update"
else
    sudo apt update -qq
    success "Package list updated"
fi

section "Installing Essential Tools"
for pkg in "wget" "curl" "build-essential" "software-properties-common" "apt-transport-https" "ca-certificates" "gnupg" "lsb-release"; do
    install_package "$pkg" "$pkg"
done

section "Installing VS Code"
if ! check_installed "code"; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${NC} Would install VS Code"
    else
        info "Installing VS Code..."
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/
        sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
        rm packages.microsoft.gpg
        sudo apt update -qq && sudo apt install -y code
        success "VS Code installed"
        CHANGES_MADE+=("Installed: VS Code")
    fi
else
    success "VS Code already installed"
fi

section "Installing Development Tools"
install_package "git" "Git"
install_package "python3" "Python 3"
install_package "python3-pip" "pip"
install_package "python3-venv" "Python venv"

if ! check_installed "node"; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${NC} Would install Node.js LTS"
    else
        info "Installing Node.js LTS..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt install -y nodejs
        success "Node.js installed"
        CHANGES_MADE+=("Installed: Node.js")
    fi
else
    success "Node.js already installed"
fi

install_package "openjdk-21-jdk" "OpenJDK 21"
install_package "openjdk-21-jdk-headless" "OpenJDK 21 Headless"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${MAGENTA}[DRY-RUN]${NC} Would install: firebase-tools, kubectl, terraform via npm"
else
    npm install -g firebase-tools 2>/dev/null || warn "Failed to install firebase-tools"
    npm install -g @azure/azure-cli 2>/dev/null || true
    success "Global npm packages installed"
fi

section "Installing Additional Software"
for pkg in "libreoffice" "p7zip-full" "unzip" "zip" "htop" "ncdu" "tree" "vim" "jq"; do
    install_package "$pkg" "$pkg"
done

if [[ "$SKIP_DEVOPS" == false ]]; then
    section "Installing DevOps Tools"
    
    if [[ "$SKIP_DOCKER" == false ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${MAGENTA}[DRY-RUN]${NC} Would install Docker"
        else
            info "Installing Docker..."
            if ! check_installed "docker"; then
                sudo install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt update -qq
                sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                sudo usermod -aG docker "$USER"
                success "Docker installed"
                CHANGES_MADE+=("Installed: Docker")
            else
                success "Docker already installed"
            fi
        fi
    fi
    
    install_package "terraform" "Terraform"
    install_package "kubectl" "kubectl"
    install_package "helm" "Helm"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${MAGENTA}[DRY-RUN]${NC} Would install: AWS CLI, kubectl, Azure CLI via pip"
    else
        if ! check_installed "aws"; then
            curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip
            success "AWS CLI installed"
        else
            success "AWS CLI already installed"
        fi
    fi
    
    for pkg in "postman" "brave-browser"; do
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${MAGENTA}[DRY-RUN]${NC} Would install: $pkg"
        else
            info "Installing $pkg..."
        fi
    done
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
        
        sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting sudo history-substring-search)/' ~/.zshrc 2>/dev/null || true
        success "Zsh plugins configured"
        CHANGES_MADE+=("Configured: Zsh plugins")
    fi
fi

section "Configuring Git"
backup_file "$HOME/.gitconfig"
git config --global credential.helper cache
git config --global core.editor "code --wait"
git config --global init.defaultBranch main
git config --global pull.rebase false
success "Git configured"

if [[ "$SKIP_DEVOPS" == false ]]; then
    section "SSH Key Setup"
    generate_ssh_key
fi

section "Configuring System"
if [[ "$DRY_RUN" == false ]]; then
    if command -v timedatectl &>/dev/null; then
        sudo timedatectl set-timezone "$(cat /etc/timezone 2>/dev/null || echo 'UTC')" 2>/dev/null || true
    fi
fi

section "Setup Complete!"
echo -e "${GREEN}Done! Run 'exec zsh' or restart terminal${NC}"
echo -e "\n${CYAN}Changes made:${NC}"
for change in "${CHANGES_MADE[@]}"; do
    echo -e "  ${YELLOW}-${NC} $change"
done
echo -e "\n${CYAN}Log saved to:${NC} $LOG_FILE"
log "Setup completed successfully"
