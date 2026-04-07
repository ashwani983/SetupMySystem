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

run_sudo() {
    local desc="$1"
    local cmd="$2"
    local ignore_errors="${3:-false}"
    
    print_cmd "$desc" "sudo $cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "    ${MAGENTA}[DRY-RUN]${NC} Command skipped${NC}"
        log "DRY-RUN: sudo $cmd"
        return 0
    fi
    
    if sudo bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS: sudo $cmd"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            warn "Command failed (ignored): sudo $cmd"
            return 0
        else
            error "Command failed: sudo $cmd"
            return 1
        fi
    fi
}

run_cmd_sudo() {
    local desc="$1"
    local cmd="$2"
    
    print_cmd "$desc" "$cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "    ${MAGENTA}[DRY-RUN]${NC} Command skipped${NC}"
        log "DRY-RUN: $cmd"
        return 0
    fi
    
    if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS: $cmd"
        return 0
    else
        warn "Command failed: $cmd"
        return 1
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
    local free_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    info "Checking disk space..."
    print_cmd "Free space: ${free_gb} GB" "df -BG /"
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

install_package() {
    local pkg="$1"
    local pkg_name="${2:-$pkg}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install: $pkg_name"
        log "DRY-RUN: Would install $pkg"
        return 0
    fi
    
    print_cmd "Checking if $pkg is installed" "dpkg -l | grep '^ii  $pkg '"
    if dpkg -l | grep -q "^ii  $pkg "; then
        success "$pkg_name already installed, skipping"
        return 0
    fi
    
    info "Installing $pkg_name..."
    run_sudo "Installing $pkg_name" "apt install -y $pkg" || warn "Failed to install $pkg_name"
    success "$pkg_name installed"
    CHANGES_MADE+=("Installed: $pkg_name")
}

section "Ubuntu System Setup"
echo -e "Log file: $LOG_FILE"
[[ "$VERBOSE" == true ]] && echo -e "Verbose mode enabled"
echo ""
log "Starting Ubuntu System Setup"
log "Parameters: DRY_RUN=$DRY_RUN, FORCE=$FORCE, VERBOSE=$VERBOSE, SKIP_ZSH=$SKIP_ZSH, SKIP_DOCKER=$SKIP_DOCKER, SKIP_DEVOPS=$SKIP_DEVOPS"

if [[ $EUID -eq 0 ]]; then
    error "Do NOT run as root!"
    exit 1
fi

check_internet || { [[ "$FORCE" == true ]] || { warn "Internet required, aborting"; exit 1; }; }
check_disk_space 15

section "Checking Existing Installations"
echo -e "  ${CYAN}Running checks for all packages...${NC}"
for cmd in code git curl wget node npm python3 java docker terraform kubectl helm aws; do
    log "Checking: $cmd"
    if check_installed "$cmd"; then
        local path
        path=$(which "$cmd" 2>/dev/null || echo "unknown")
        success "$cmd is installed ($path)"
    else
        info "$cmd not found"
    fi
done

section "Updating Package List"
run_sudo "Updating apt package list" "apt update -qq"

section "Installing Essential Tools"
for pkg in "wget" "curl" "build-essential" "software-properties-common" "apt-transport-https" "ca-certificates" "gnupg" "lsb-release" "unzip" "zip" "htop" "ncdu" "tree" "vim" "jq"; do
    install_package "$pkg" "$pkg"
done

section "Installing VS Code"
if ! check_installed "code"; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install VS Code"
        log "DRY-RUN: Would install VS Code"
    else
        info "Installing VS Code..."
        run_cmd "Downloading Microsoft GPG key" "wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg"
        run_sudo "Installing GPG key" "install -D -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/"
        run_sudo "Adding VS Code repository" "sh -c 'echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main\" > /etc/apt/sources.list.d/vscode.list'"
        run_cmd "Cleaning up GPG file" "rm packages.microsoft.gpg"
        run_sudo "Installing VS Code" "apt update -qq && apt install -y code"
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
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Node.js LTS"
        log "DRY-RUN: Would install Node.js LTS"
    else
        info "Installing Node.js LTS..."
        run_cmd "Downloading NodeSource script" "curl -fsSL https://deb.nodesource.com/setup_lts.x"
        run_sudo "Installing Node.js" "bash -c 'curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && apt install -y nodejs'"
        success "Node.js installed"
        CHANGES_MADE+=("Installed: Node.js")
    fi
else
    success "Node.js already installed"
fi

install_package "openjdk-21-jdk" "OpenJDK 21"
install_package "openjdk-21-jdk-headless" "OpenJDK 21 Headless"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install npm packages: firebase-tools, azure-cli"
    log "DRY-RUN: Would install npm global packages"
else
    run_cmd "Installing firebase-tools" "npm install -g firebase-tools"
    run_cmd "Installing azure-cli" "npm install -g @azure/azure-cli" || true
    success "Global npm packages installed"
fi

section "Installing Additional Software"
for pkg in "libreoffice" "p7zip-full"; do
    install_package "$pkg" "$pkg"
done

if [[ "$SKIP_DEVOPS" == false ]]; then
    section "Installing DevOps Tools"
    
    if [[ "$SKIP_DOCKER" == false ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Docker"
            log "DRY-RUN: Would install Docker"
        else
            if ! check_installed "docker"; then
                info "Installing Docker..."
                run_sudo "Creating apt keyrings directory" "install -m 0755 -d /etc/apt/keyrings"
                run_cmd_sudo "Downloading Docker GPG key" "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
                run_sudo "Adding Docker repository" "sh -c 'echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list'"
                run_sudo "Updating package list" "apt update -qq"
                run_sudo "Installing Docker packages" "apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
                run_sudo "Adding user to docker group" "usermod -aG docker $USER"
                success "Docker installed"
                CHANGES_MADE+=("Installed: Docker")
            else
                success "Docker already installed"
            fi
        fi
    fi
    
    install_package "terraform" "Terraform"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install kubectl and helm"
        log "DRY-RUN: Would install kubectl and helm"
    else
        if ! check_installed "kubectl"; then
            info "Installing kubectl..."
            run_sudo "Downloading kubectl" "curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
            run_sudo "Installing kubectl" "install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
            run_cmd "Cleaning up kubectl download" "rm -f kubectl"
            success "kubectl installed"
        else
            success "kubectl already installed"
        fi
        
        if ! check_installed "helm"; then
            info "Installing Helm..."
            run_cmd_sudo "Downloading Helm install script" "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
            success "Helm installed"
        else
            success "Helm already installed"
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install AWS CLI"
        log "DRY-RUN: Would install AWS CLI"
    else
        if ! check_installed "aws"; then
            info "Installing AWS CLI..."
            run_cmd "Downloading AWS CLI v2" "curl -s \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\""
            run_cmd "Unzipping AWS CLI" "unzip -q awscliv2.zip"
            run_sudo "Installing AWS CLI" "./aws/install"
            run_cmd "Cleaning up AWS CLI files" "rm -rf aws awscliv2.zip"
            success "AWS CLI installed"
        else
            success "AWS CLI already installed"
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Bruno"
        log "DRY-RUN: Would install Bruno"
    else
        if ! check_installed "bruno"; then
            info "Installing Bruno..."
            run_cmd "Downloading Bruno" "npm install -g bruno"
            success "Bruno installed"
        else
            success "Bruno already installed"
        fi
    fi
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
        
        declare -A plugins=(
            ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
            ["zsh-completions"]="https://github.com/zsh-users/zsh-completions"
            ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
            ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search.git"
        )
        
        for plugin in "${!plugins[@]}"; do
            if [ ! -d "$zsh_custom/plugins/$plugin" ]; then
                info "Installing $plugin..."
                run_cmd "Cloning $plugin" "git clone ${plugins[$plugin]} $zsh_custom/plugins/$plugin"
            fi
        done
        
        run_cmd "Updating Zsh plugins" "sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting sudo history-substring-search)/' ~/.zshrc"
        success "Zsh plugins configured"
        CHANGES_MADE+=("Configured: Zsh plugins")
    fi
fi

section "Configuring Git"
backup_file "$HOME/.gitconfig"
declare -A git_configs=(
    ["credential.helper"]="cache"
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
        echo -e "${YELLOW}4.${NC} Log out and back in for Docker group membership"
        echo -e "   Then verify: ${CYAN}docker run hello-world${NC}"
    fi
fi
