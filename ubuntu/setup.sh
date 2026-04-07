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

run_sudo() {
    local desc="$1"
    local cmd="$2"
    local ignore_errors="${3:-false}"
    
    print_cmd "$desc" "sudo $cmd"
    log "EXEC" "EXECUTING: sudo $cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "    ${MAGENTA}[DRY-RUN] Skipped${NC}"
        log "INFO" "DRY-RUN: sudo $cmd skipped"
        return 0
    fi
    
    local output
    local exit_code=0
    
    output=$(sudo bash -c "$cmd" 2>&1) || exit_code=$?
    
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
            ERRORS+=("sudo $cmd : Exit code $exit_code")
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
    free_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
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

install_package() {
    local pkg="$1"
    local pkg_name="${2:-$pkg}"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install: $pkg_name"
        log "INFO" "DRY-RUN: Would install $pkg_name"
        return 0
    fi
    
    if dpkg -l | grep -q "^ii  $pkg "; then
        echo -e "${GREEN}    [OK]${NC} $pkg_name already installed, skipping"
        log "CHECK" "$pkg_name already installed"
        return 0
    fi
    
    echo -e "${CYAN}  Installing $pkg_name...${NC}"
    log "INSTALL" "Installing $pkg_name ($pkg)"
    
    if sudo apt install -y "$pkg" &>/dev/null; then
        echo -e "${GREEN}    [OK]${NC} $pkg_name installed"
        log "RESULT" "SUCCESS: $pkg_name installed"
        CHANGES_MADE+=("Installed: $pkg_name")
    else
        echo -e "${YELLOW}    [!]${NC} Failed to install $pkg_name"
        log "ERROR" "FAILED: $pkg_name installation"
        ERRORS+=("$pkg_name installation failed")
    fi
}

section "Ubuntu System Setup"
echo -e "  ${DARK}Log file: $LOG_FILE${NC}"
[[ "$VERBOSE" == true ]] && echo -e "  ${DARK}Verbose mode enabled${NC}"
echo ""
log "========================================" "INFO"
log "Starting Ubuntu System Setup" "INFO"
log "Parameters: DRY_RUN=$DRY_RUN, FORCE=$FORCE, SKIP_ZSH=$SKIP_ZSH, SKIP_DOCKER=$SKIP_DOCKER, SKIP_DEVOPS=$SKIP_DEVOPS" "INFO"

if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}    [X]${NC} Do NOT run as root!"
    exit 1
fi

check_sudo() {
    echo -e "${CYAN}  Checking sudo access...${NC}"
    if sudo -v 2>/dev/null; then
        echo -e "${GREEN}    [OK]${NC} Sudo access available"
        log "CHECK" "Sudo access: OK"
        return 0
    else
        echo -e "${RED}    [X]${NC} Sudo access required but not available"
        echo -e "${YELLOW}    [!]${NC} Please ensure you have sudo privileges"
        echo -e "      Try: ${CYAN}sudo ls${NC} to verify"
        log "ERROR" "Sudo access: NOT AVAILABLE"
        return 1
    fi
}

check_sudo || { echo -e "${YELLOW}    [!]${NC} Continuing without sudo check - some installations may fail"; }

check_internet || { [[ "$FORCE" == true ]] || { echo -e "${YELLOW}    [!]${NC} Internet required, aborting"; exit 1; }; }
check_disk_space 15

section "Checking Existing Installations"
echo -e "  ${CYAN}Running checks for all packages...${NC}"
log "INFO" "Checking installed packages..."
for cmd in code git curl wget node npm python3 java docker terraform kubectl helm aws bruno; do
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
        log "INFO" "DRY-RUN: Would install VS Code"
    else
        echo -e "${CYAN}  Installing VS Code...${NC}"
        log "INSTALL" "Installing VS Code"
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg 2>/dev/null
        sudo install -D -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/ 2>/dev/null
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        rm packages.microsoft.gpg
        sudo apt update -qq && sudo apt install -y code &>/dev/null
        if check_installed "code"; then
            echo -e "${GREEN}    [OK]${NC} VS Code installed"
            log "RESULT" "SUCCESS: VS Code installed"
            CHANGES_MADE+=("Installed: VS Code")
        else
            echo -e "${YELLOW}    [!]${NC} VS Code installation may have failed"
            log "WARN" "VS Code installation may have failed"
        fi
    fi
else
    echo -e "${GREEN}    [OK]${NC} VS Code already installed"
fi

section "Installing Development Tools"
install_package "git" "Git"
install_package "python3" "Python 3"
install_package "python3-pip" "pip"
install_package "python3-venv" "Python venv"

if ! check_installed "node"; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Node.js LTS"
        log "INFO" "DRY-RUN: Would install Node.js LTS"
    else
        echo -e "${CYAN}  Installing Node.js LTS...${NC}"
        log "INSTALL" "Installing Node.js LTS"
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - &>/dev/null && sudo apt install -y nodejs &>/dev/null
        if check_installed "node"; then
            echo -e "${GREEN}    [OK]${NC} Node.js installed"
            log "RESULT" "SUCCESS: Node.js installed"
            CHANGES_MADE+=("Installed: Node.js")
        else
            echo -e "${YELLOW}    [!]${NC} Node.js installation may have failed"
        fi
    fi
else
    echo -e "${GREEN}    [OK]${NC} Node.js already installed"
fi

install_package "openjdk-21-jdk" "OpenJDK 21"
install_package "openjdk-21-jdk-headless" "OpenJDK 21 Headless"

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

section "Installing Additional Software"
for pkg in "libreoffice" "p7zip-full"; do
    install_package "$pkg" "$pkg"
done

if [[ "$SKIP_DEVOPS" == false ]]; then
    section "Installing DevOps Tools"
    
    if [[ "$SKIP_DOCKER" == false ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Docker"
            log "INFO" "DRY-RUN: Would install Docker"
        else
            if ! check_installed "docker"; then
                echo -e "${CYAN}  Installing Docker...${NC}"
                log "INSTALL" "Installing Docker"
                sudo install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt update -qq
                sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>/dev/null
                sudo usermod -aG docker "$USER" 2>/dev/null || true
                if check_installed "docker"; then
                    echo -e "${GREEN}    [OK]${NC} Docker installed"
                    log "RESULT" "SUCCESS: Docker installed"
                    CHANGES_MADE+=("Installed: Docker")
                else
                    echo -e "${YELLOW}    [!]${NC} Docker installation may have failed"
                fi
            else
                echo -e "${GREEN}    [OK]${NC} Docker already installed"
            fi
        fi
    fi
    
    install_package "terraform" "Terraform"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install kubectl and helm"
    else
        if ! check_installed "kubectl"; then
            echo -e "${CYAN}  Installing kubectl...${NC}"
            log "INSTALL" "Installing kubectl"
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" 2>/dev/null
            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl 2>/dev/null
            rm -f kubectl
            if check_installed "kubectl"; then
                echo -e "${GREEN}    [OK]${NC} kubectl installed"
                CHANGES_MADE+=("Installed: kubectl")
            fi
        else
            echo -e "${GREEN}    [OK]${NC} kubectl already installed"
        fi
        
        if ! check_installed "helm"; then
            echo -e "${CYAN}  Installing Helm...${NC}"
            log "INSTALL" "Installing Helm"
            curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash &>/dev/null
            if check_installed "helm"; then
                echo -e "${GREEN}    [OK]${NC} Helm installed"
                CHANGES_MADE+=("Installed: Helm")
            fi
        else
            echo -e "${GREEN}    [OK]${NC} Helm already installed"
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install AWS CLI"
    else
        if ! check_installed "aws"; then
            echo -e "${CYAN}  Installing AWS CLI...${NC}"
            log "INSTALL" "Installing AWS CLI"
            curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip -q awscliv2.zip
            sudo ./aws/install &>/dev/null
            rm -rf aws awscliv2.zip
            if check_installed "aws"; then
                echo -e "${GREEN}    [OK]${NC} AWS CLI installed"
                CHANGES_MADE+=("Installed: AWS CLI")
            fi
        else
            echo -e "${GREEN}    [OK]${NC} AWS CLI already installed"
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${MAGENTA}[DRY-RUN]${NC} Would install Bruno"
    else
        if ! check_installed "bruno"; then
            echo -e "${CYAN}  Installing Bruno via npm...${NC}"
            log "INSTALL" "Installing Bruno"
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
        
        sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting sudo history-substring-search)/' ~/.zshrc 2>/dev/null || true
        echo -e "${GREEN}    [OK]${NC} Zsh plugins configured"
        CHANGES_MADE+=("Configured: Zsh plugins")
    fi
fi

section "Configuring Git"
backup_file "$HOME/.gitconfig"
git config --global credential.helper cache
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

section "Setup Complete!"

local success_count=0
local warn_count=0

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
        echo -e "${YELLOW}4.${NC} Log out and back in for Docker group membership"
        echo -e "   Then verify: ${CYAN}docker run hello-world${NC}"
    fi
fi
