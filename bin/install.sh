#!/bin/bash
# Quick installer script for UDS k3d Cilium tools
# Usage: curl -sL https://raw.githubusercontent.com/mkm29/uds-tooling/main/bin/install.sh | bash
# This script checks dependencies and runs use-tools-artifact.sh which uses ORAS to pull the tools

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect OS and architecture
OS=$(uname -s)
ARCH=$(uname -m)

# Convert architecture names
case ${ARCH} in
x86_64)
    ARCH="amd64"
    ;;
aarch64)
    ARCH="arm64"
    ;;
arm64)
    # macOS already uses arm64
    ;;
*)
    echo "Error: Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

# Convert OS names for downloads
OS_LOWER=$(echo "${OS}" | tr '[:upper:]' '[:lower:]')

echo "🚀 Installing UDS k3d Cilium tools for ${OS}/${ARCH}..."
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Function to install oras
install_oras() {
    echo -e "${YELLOW}📦 Installing ORAS CLI...${NC}"

    if [[ "${OS}" == "Darwin" ]]; then
        if command_exists brew; then
            echo "Using Homebrew to install ORAS..."
            brew install oras
        else
            echo -e "${RED}Error: Homebrew is not installed. Please install Homebrew first:${NC}"
            echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
    elif [[ "${OS}" == "Linux" ]]; then
        echo "Downloading ORAS from GitHub releases..."
        ORAS_VERSION="1.2.3"
        ORAS_URL="https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_${OS_LOWER}_${ARCH}.tar.gz"

        TEMP_ORAS=$(mktemp -d)
        curl -sL "${ORAS_URL}" -o "${TEMP_ORAS}/oras.tar.gz"
        tar -xzf "${TEMP_ORAS}/oras.tar.gz" -C "${TEMP_ORAS}"

        # Install to user's local bin directory
        mkdir -p "$HOME/.local/bin"
        install -m 755 "${TEMP_ORAS}/oras" "$HOME/.local/bin/oras"
        echo -e "${GREEN}✓ ORAS installed to ~/.local/bin/oras${NC}"

        # Add to PATH for this session if not already present
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo -e "${YELLOW}  Adding ~/.local/bin to PATH for this session${NC}"
            export PATH="$HOME/.local/bin:$PATH"
        fi

        rm -rf "${TEMP_ORAS}"
    else
        echo -e "${RED}Error: Unsupported OS for automatic ORAS installation${NC}"
        echo "Please install ORAS manually from: https://oras.land/docs/installation"
        exit 1
    fi
}

# Function to install jq
install_jq() {
    echo -e "${YELLOW}📦 Installing jq...${NC}"

    if [[ "${OS}" == "Darwin" ]]; then
        if command_exists brew; then
            echo "Using Homebrew to install jq..."
            brew install jq
        else
            echo -e "${RED}Error: Homebrew is not installed. Please install Homebrew first:${NC}"
            echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
    elif [[ "${OS}" == "Linux" ]]; then
        echo "Downloading jq from GitHub releases..."
        JQ_VERSION="1.7.1"
        JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-${OS_LOWER}-${ARCH}"

        TEMP_JQ=$(mktemp)
        curl -sL "${JQ_URL}" -o "${TEMP_JQ}"

        # Install to user's local bin directory
        mkdir -p "$HOME/.local/bin"
        install -m 755 "${TEMP_JQ}" "$HOME/.local/bin/jq"
        echo -e "${GREEN}✓ jq installed to ~/.local/bin/jq${NC}"

        # Add to PATH for this session if not already present
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo -e "${YELLOW}  Adding ~/.local/bin to PATH for this session${NC}"
            export PATH="$HOME/.local/bin:$PATH"
        fi

        rm -f "${TEMP_JQ}"
    else
        echo -e "${RED}Error: Unsupported OS for automatic jq installation${NC}"
        echo "Please install jq manually from: https://jqlang.org/download/"
        exit 1
    fi
}

# Check for required dependencies
echo "🔍 Checking dependencies..."

# Check for oras
if ! command_exists oras; then
    echo -e "${YELLOW}⚠ ORAS CLI not found${NC}"
    read -p "Would you like to install ORAS? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_oras
    else
        echo -e "${RED}Error: ORAS is required. Please install it manually:${NC}"
        echo "  macOS: brew install oras"
        echo "  Linux: Download from https://github.com/oras-project/oras/releases"
        echo "  Docs: https://oras.land/docs/installation"
        exit 1
    fi
else
    echo -e "${GREEN}✓ ORAS CLI found${NC}"
fi

# Check for jq
if ! command_exists jq; then
    echo -e "${YELLOW}⚠ jq not found${NC}"
    read -p "Would you like to install jq? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_jq
    else
        echo -e "${RED}Error: jq is required. Please install it manually:${NC}"
        echo "  macOS: brew install jq"
        echo "  Linux: Download from https://github.com/jqlang/jq/releases"
        echo "  Docs: https://jqlang.org/download/"
        exit 1
    fi
else
    echo -e "${GREEN}✓ jq found${NC}"
fi

echo ""

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf ${TEMP_DIR}' EXIT

# Download the required scripts and configuration
echo "📥 Downloading installer scripts..."

# Download common.sh (required by use-tools-artifact.sh)
if ! curl -sL https://raw.githubusercontent.com/mkm29/uds-tooling/main/bin/common.sh -o "${TEMP_DIR}/common.sh"; then
    echo -e "${RED}Error: Failed to download common.sh${NC}"
    exit 1
fi

# Download tools-config.json (required for tool definitions)
if ! curl -sL https://raw.githubusercontent.com/mkm29/uds-tooling/main/tools-config.json -o "${TEMP_DIR}/tools-config.json"; then
    echo -e "${RED}Error: Failed to download tools-config.json${NC}"
    exit 1
fi

# Download use-tools-artifact.sh
if ! curl -sL https://raw.githubusercontent.com/mkm29/uds-tooling/main/bin/use-tools-artifact.sh -o "${TEMP_DIR}/use-tools-artifact.sh"; then
    echo -e "${RED}Error: Failed to download use-tools-artifact.sh${NC}"
    exit 1
fi

chmod +x "${TEMP_DIR}/use-tools-artifact.sh"

# Check if we need to remind about PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Note: Add ~/.local/bin to your PATH permanently by adding this to your shell config:${NC}"
    echo -e "${GREEN}  export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
fi

# Run the installer from the temp directory
echo ""
cd "${TEMP_DIR}"
exec "./use-tools-artifact.sh" "$@"
