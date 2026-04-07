#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

print_section() {
    echo -e "\n${CYAN}========================================"
    echo -e " $1"
    echo -e "========================================${NC}\n"
}

if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}ERROR: Do NOT run as root!${NC}"
    exit 1
fi

print_section "Ubuntu System Setup"
echo -e "${GREEN}Starting Ubuntu System Setup...${NC}"
print_section "Updating Package List"
sudo apt update -qq

print_section "Installing VS Code"
if ! command -v code &> /dev/null; then
    sudo apt install -y wget gpg
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -D -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/
    sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    rm packages.microsoft.gpg
    sudo apt update -qq && sudo apt install -y code
fi

print_section "Installing Development Tools"
sudo apt install -y git curl wget build-essential
if ! command -v node &> /dev/null; then curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt install -y nodejs; fi
sudo apt install -y python3 python3-pip python3-venv openjdk-21-jdk
npm install -g firebase-tools

print_section "Installing Additional Software"
sudo apt install -y android-sdk-platform-tools libreoffice p7zip-full

print_section "Installing oh-my-zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; fi
ZSH_CUSTOM="${HOME}/.oh-my-zsh/custom"
git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" 2>/dev/null || true
git clone https://github.com/zsh-users/zsh-completions "${ZSH_CUSTOM}/plugins/zsh-completions" 2>/dev/null || true
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" 2>/dev/null || true
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting sudo)/' ~/.zshrc 2>/dev/null || true

echo -e "${GREEN}Done! Run 'exec zsh' or restart terminal${NC}"
