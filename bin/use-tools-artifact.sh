#!/bin/bash
set -euo pipefail

# Script to download and install CLI tools using ORAS

# Parse command line arguments
FORCE_INSTALL=false
while [[ $# -gt 0 ]]; do
    case $1 in
    --force | -f)
        FORCE_INSTALL=true
        shift
        ;;
    --help | -h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --force, -f    Force installation even if tools are already installed"
        echo "  --help, -h     Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  REGISTRY       Override registry (default: ghcr.io)"
        echo "  NAMESPACE      Override namespace (default: mkm29)"
        echo "  REPOSITORY     Override repository (default: uds-tooling/tools)"
        echo "  TAG            Override tag (default: from tools-config.json)"
        echo "  INSTALL_PATH   Installation directory (default: ~/.local/bin)"
        echo ""
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
done

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/common.sh
source "${SCRIPT_DIR}/common.sh"

# Load tools configuration
if ! load_tools_config; then
    echo "Failed to load tools configuration"
    exit 1
fi

# Detect platform
PLATFORM=$(detect_platform)
if [ $? -ne 0 ]; then
    echo "Failed to detect platform"
    exit 1
fi

OS=$(echo "${PLATFORM}" | cut -d'/' -f1)
ARCH=$(echo "${PLATFORM}" | cut -d'/' -f2)

# Configuration from JSON with environment overrides
REGISTRY="${REGISTRY:-$(get_artifact_config 'registry')}"
NAMESPACE="${NAMESPACE:-$(get_artifact_config 'namespace')}"
REPOSITORY="${REPOSITORY:-$(get_artifact_config 'repository')}"
TAG="${TAG:-$(get_artifact_config 'default_tag')}"
INSTALL_PATH="${INSTALL_PATH:-$HOME/.local/bin}"

# Full image name
IMAGE="${REGISTRY}/${NAMESPACE}/${REPOSITORY}:${TAG}"

echo "📦 UDS k3d Cilium Tools Installer (ORAS)"
echo "========================================"
echo ""
echo "Detected platform: ${OS}/${ARCH}"
echo "Installing to: ${INSTALL_PATH}"
echo ""

# Check if jq is installed (needed for manifest parsing)
if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}Warning: jq is not installed. Installing jq for JSON parsing...${NC}"

    # Try to install jq based on OS
    if [ "${OS}" = "darwin" ]; then
        if command -v brew &>/dev/null; then
            brew install jq
        else
            echo -e "${RED}Please install jq: brew install jq${NC}"
            exit 1
        fi
    elif [ "${OS}" = "linux" ]; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &>/dev/null; then
            sudo yum install -y jq
        else
            echo -e "${RED}Please install jq manually${NC}"
            exit 1
        fi
    fi
fi

# Install ORAS if needed
if ! install_oras "${INSTALL_PATH}"; then
    exit 1
fi

# Create install directory if it doesn't exist
mkdir -p "${INSTALL_PATH}"

# Create temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap 'rm -rf ${TEMP_DIR}' EXIT

echo "⬇️  Pulling tools artifact: ${IMAGE}"
echo ""

# Check authentication (but don't exit if it fails - might be public)
oras_login "${REGISTRY}" "${NAMESPACE}" || true

# Check if this is an ORAS artifact with file annotations by trying to fetch manifest
echo "Detecting artifact type..."
MANIFEST=$(oras manifest fetch "${IMAGE}" 2>/dev/null || echo "")

if [ -z "$MANIFEST" ]; then
    echo -e "${RED}Failed to fetch manifest. Please check authentication and image existence.${NC}"
    exit 1
fi

# Check if it's an ORAS artifact (has file annotations)
if echo "$MANIFEST" | jq -e '.layers[0].annotations."org.opencontainers.image.title"' &>/dev/null; then
    # It's an ORAS artifact
    echo "Detected ORAS artifact"

    # For ORAS artifacts, we need to use platform-specific tags
    PLATFORM_IMAGE="${IMAGE}-${OS}-${ARCH}"
    echo "Pulling ${PLATFORM_IMAGE}..."

    if ! oras pull "${PLATFORM_IMAGE}" \
        -o "${TEMP_DIR}"; then
        echo ""
        echo -e "${RED}Failed to pull ORAS artifact.${NC}"
        echo "This might be because:"
        echo "1. The platform-specific tag doesn't exist"
        echo "2. Authentication is required"
        echo ""
        echo "Trying base tag with platform flag..."
        # Try with platform flag as fallback
        if ! oras pull "${IMAGE}" -o "${TEMP_DIR}"; then
            echo -e "${RED}Failed to pull ORAS artifact.${NC}"
            echo "See tools/SETUP.md for detailed setup instructions."
            exit 1
        fi
    fi
else
    # It's not an ORAS artifact with file annotations
    echo "Detected non-ORAS artifact (missing file annotations)"
    echo ""
    echo -e "${RED}Error: This artifact was not built with ORAS file annotations.${NC}"
    echo "ORAS can only extract from ORAS artifacts with file annotations."
    echo ""
    echo "To fix this:"
    echo "1. Build with ORAS: ./bin/build.sh"
    echo "2. Or pull a pre-built ORAS artifact"
    echo ""
    exit 1
fi

# Install tools
echo ""
echo "🔧 Installing tools to ${INSTALL_PATH}..."

# ORAS artifacts have flat structure
TOOLS_DIR="${TEMP_DIR}"

for tool in $(get_all_tools); do
    executable_name=$(get_tool_property "$tool" "executable_name")
    tool_name=$(get_tool_property "$tool" "name")

    # Check if tool is already installed
    if command -v "${executable_name}" &>/dev/null && [ "$FORCE_INSTALL" = false ]; then
        # Get installed version based on tool
        installed_version=""
        case "${executable_name}" in
        kubectl)
            installed_version=$("${executable_name}" version --client --short 2>/dev/null || echo "unknown")
            ;;
        k9s)
            installed_version=$("${executable_name}" version -s 2>/dev/null || echo "unknown")
            ;;
        *)
            installed_version=$("${executable_name}" version 2>/dev/null | head -n1 || echo "unknown")
            ;;
        esac
        echo -e "  ${YELLOW}⚠${NC} ${tool_name} already installed: ${installed_version}"
        echo "     Skipping installation. Use --force to override."
        continue
    fi

    if [ -f "${TOOLS_DIR}/${executable_name}" ]; then
        # Use install command for proper permissions and ownership
        if command -v install &>/dev/null; then
            install -m 755 "${TOOLS_DIR}/${executable_name}" "${INSTALL_PATH}/${executable_name}"
        else
            # Fallback to cp and chmod if install is not available
            cp "${TOOLS_DIR}/${executable_name}" "${INSTALL_PATH}/${executable_name}"
            chmod +x "${INSTALL_PATH}/${executable_name}"
        fi
        echo -e "  ${GREEN}✓${NC} ${tool_name} installed to ${INSTALL_PATH}"
    else
        echo -e "  ${RED}✗${NC} ${tool_name} not found in artifact"
    fi
done

# Verify installations
echo ""
echo "🔍 Verifying installations..."
echo ""

# Check if install path is in PATH
if [[ ":$PATH:" != *":${INSTALL_PATH}:"* ]]; then
    echo -e "${YELLOW}Warning: ${INSTALL_PATH} is not in your PATH${NC}"
    echo ""
    echo "Add it to your shell configuration:"
    echo "  export PATH=\"${INSTALL_PATH}:\$PATH\""
    echo ""
fi

# Verify each tool
for tool in $(get_all_tools); do
    executable_name=$(get_tool_property "$tool" "executable_name")
    tool_name=$(get_tool_property "$tool" "name")

    # Check in PATH first, then in INSTALL_PATH
    tool_path=""
    if command -v "${executable_name}" &>/dev/null; then
        tool_path=$(command -v "${executable_name}")
    elif [ -f "${INSTALL_PATH}/${executable_name}" ]; then
        tool_path="${INSTALL_PATH}/${executable_name}"
    fi

    if [ -n "$tool_path" ]; then
        # Get version based on tool
        version=""
        case "${executable_name}" in
        kubectl)
            version=$("${tool_path}" version --client --short 2>/dev/null || echo "unknown")
            ;;
        k9s)
            version=$("${tool_path}" version -s 2>/dev/null || echo "unknown")
            ;;
        *)
            version=$("${tool_path}" version 2>/dev/null | head -n1 || echo "unknown")
            ;;
        esac
        echo -e "  ${tool_name}: ${GREEN}${version}${NC} (${tool_path})"
    else
        echo -e "  ${tool_name}: ${RED}not found${NC}"
    fi
done

echo ""
echo -e "${GREEN}✅ Tools installation complete!${NC}"
echo ""
echo "If ${INSTALL_PATH} is in your PATH, you can now use:"
for tool in $(get_all_tools); do
    executable_name=$(get_tool_property "$tool" "executable_name")
    if [ "$executable_name" = "k9s" ]; then
        echo "  ${executable_name}"
    else
        echo "  ${executable_name} version"
    fi
done
