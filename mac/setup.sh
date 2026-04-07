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

print_section "macOS System Setup"

echo -e "${GREEN}Starting macOS System Setup...${NC}"
read -p "Continue? (Y/n) " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! $REPLY == "" ]] && exit 0

print_section "Checking for Homebrew"
if ! command -v brew &> /dev/null; then
    echo -e "${CYAN}Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

print_section "Installing Software"
brew install --cask visual-studio-code
brew install git node python3 openjdk@21
npm install -g firebase-tools
brew install --cask android-platform-tools libreoffice xampp
brew install --cask double-commander
brew install p7zip
brew cleanup -q

print_section "Installing oh-my-zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="${HOME}/.oh-my-zsh/custom"
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
[ ! -d "$ZSH_CUSTOM/plugins/zsh-completions" ] && git clone https://github.com/zsh-users/zsh-completions "${ZSH_CUSTOM}/plugins/zsh-completions"
[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"

sed -i '' 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting sudo)/' ~/.zshrc

echo -e "${GREEN}Done! Run 'exec zsh' or restart terminal${NC}"
