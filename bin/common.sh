#!/bin/bash
# Common functions for UDS k3d Cilium tools scripts
#
# This file provides shared functions for:
# - ORAS authentication
# - Platform detection
# - Tool installation
# - Download utilities
#
# Source this file in other scripts:
#   source "${SCRIPT_DIR}/common.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Function to check ORAS authentication
check_oras_auth() {
    local registry="${1:-ghcr.io}"
    local namespace="${2:-}"
    local test_image="${registry}/${namespace}/test:latest"

    echo "Checking ORAS authentication for ${registry}..."

    # Try to fetch manifest to check auth
    if oras manifest fetch "$test_image" &>/dev/null; then
        echo "✓ Authenticated to ${registry}"
        return 0
    else
        return 1
    fi
}

# Function to login to registry using ORAS
oras_login() {
    local registry="${1:-ghcr.io}"
    local namespace="${2:-}"
    local username="${3:-$namespace}"

    # Check if already authenticated
    if check_oras_auth "$registry" "$namespace"; then
        return 0
    fi

    echo ""
    echo "⚠️  Not authenticated to ${registry}"

    # GitHub Container Registry
    if [[ "$registry" == "ghcr.io" ]]; then
        if [ -n "${CR_PAT:-}" ]; then
            echo ""
            echo "🔐 Attempting automatic login using CR_PAT environment variable..."

            if echo "${CR_PAT}" | oras login ghcr.io -u "$username" --password-stdin &>/dev/null; then
                echo "✓ Successfully authenticated to GitHub Container Registry"
                echo ""
                return 0
            else
                echo "❌ Automatic login failed"
                echo ""
                echo "Please verify:"
                echo "1. CR_PAT environment variable contains a valid GitHub Personal Access Token"
                echo "2. The token has 'write:packages' scope"
                echo "3. Username ($username) matches your GitHub username"
                echo ""
                return 1
            fi
        else
            echo ""
            echo "To authenticate:"
            echo "  export CR_PAT=YOUR_TOKEN"
            echo "  echo \$CR_PAT | oras login ghcr.io -u YOUR_USERNAME --password-stdin"
            echo ""
            return 1
        fi
    fi

    # Docker Hub
    if [[ "$registry" == "docker.io" ]]; then
        echo ""
        echo "To authenticate:"
        echo "  oras login docker.io"
        echo ""
        return 1
    fi

    # Other registries
    echo ""
    echo "To authenticate:"
    echo "  oras login $registry"
    echo ""
    return 1
}

# Function to install ORAS if not present
install_oras() {
    local install_path="${1:-$HOME/.local/bin}"

    if command_exists oras; then
        return 0
    fi

    echo -e "${RED}Error: oras is not installed${NC}"
    echo ""
    echo "Installing ORAS CLI..."

    # Detect OS and architecture
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)

    # Convert architecture names
    case ${arch} in
    x86_64)
        arch="amd64"
        ;;
    aarch64 | arm64)
        arch="arm64"
        ;;
    *)
        echo "Unsupported architecture: ${arch}"
        return 1
        ;;
    esac

    # Download and install ORAS
    local oras_version="1.2.3"
    local oras_url="https://github.com/oras-project/oras/releases/download/v${oras_version}/oras_${oras_version}_${os}_${arch}.tar.gz"

    # Create temp directory for ORAS download
    local temp_dir=$(mktemp -d)
    trap "rm -rf ${temp_dir}" RETURN

    echo "Downloading ORAS v${oras_version}..."
    if curl -fsSL "${oras_url}" -o "${temp_dir}/oras.tar.gz"; then
        tar -xzf "${temp_dir}/oras.tar.gz" -C "${temp_dir}"

        # Install ORAS to install_path
        mkdir -p "${install_path}"
        mv "${temp_dir}/oras" "${install_path}/oras"
        chmod +x "${install_path}/oras"
        echo -e "${GREEN}✓ ORAS installed successfully${NC}"

        # Check if install_path is in PATH
        if [[ ":$PATH:" != *":${install_path}:"* ]]; then
            echo -e "${YELLOW}Note: Add ${install_path} to your PATH to use oras command${NC}"
            export PATH="${install_path}:$PATH"
        fi

        return 0
    else
        echo -e "${RED}Failed to download ORAS${NC}"
        echo "Please install ORAS manually from: https://oras.land/docs/installation"
        return 1
    fi
}

# Function to download with retries
download_with_retry() {
    local url=$1
    local output=$2
    local max_retries=${3:-3}
    local retry=0

    while [ $retry -lt $max_retries ]; do
        if curl -fL --progress-bar "${url}" -o "${output}"; then
            return 0
        else
            retry=$((retry + 1))
            echo "  Retry ${retry}/${max_retries}..."
            sleep 2
        fi
    done

    echo -e "  ${RED}❌ Failed to download after ${max_retries} attempts${NC}"
    return 1
}

# Function to detect platform
detect_platform() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)

    # Convert architecture names
    case ${arch} in
    x86_64)
        arch="amd64"
        ;;
    aarch64)
        arch="arm64"
        ;;
    arm64)
        # macOS already uses arm64
        ;;
    *)
        echo "Unsupported architecture: ${arch}" >&2
        return 1
        ;;
    esac

    echo "${os}/${arch}"
}

# Export functions and variables
export -f command_exists
export -f check_oras_auth
export -f oras_login
export -f install_oras
export -f download_with_retry
export -f detect_platform
export RED GREEN YELLOW NC

# JSON Configuration Functions
# ============================

# Function to load JSON configuration
load_tools_config() {
    local config_file="${1:-${SCRIPT_DIR}/tools-config.json}"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error: Configuration file not found: $config_file${NC}" >&2
        return 1
    fi

    # Check if jq is available
    if ! command_exists jq; then
        echo -e "${RED}Error: jq is required for JSON parsing${NC}" >&2
        echo "Please install jq: https://stedolan.github.io/jq/download/" >&2
        return 1
    fi

    # Validate JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        echo -e "${RED}Error: Invalid JSON in configuration file${NC}" >&2
        return 1
    fi

    # Export the config file path for use in other functions
    export TOOLS_CONFIG_FILE="$config_file"
    return 0
}

# Function to get tool property from JSON config
get_tool_property() {
    local tool_key="$1"
    local property="$2"
    local config_file="${TOOLS_CONFIG_FILE:-${SCRIPT_DIR}/tools-config.json}"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error: Configuration file not found${NC}" >&2
        return 1
    fi

    jq -r ".tools.${tool_key}.${property} // empty" "$config_file"
}

# Function to get all tool keys
get_all_tools() {
    local config_file="${TOOLS_CONFIG_FILE:-${SCRIPT_DIR}/tools-config.json}"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error: Configuration file not found${NC}" >&2
        return 1
    fi

    jq -r '.tools | keys[]' "$config_file"
}

# Function to get artifact configuration
get_artifact_config() {
    local property="$1"
    local config_file="${TOOLS_CONFIG_FILE:-${SCRIPT_DIR}/tools-config.json}"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error: Configuration file not found${NC}" >&2
        return 1
    fi

    jq -r ".artifact.${property} // empty" "$config_file"
}

# Function to build tool URL from pattern
build_tool_url() {
    local tool_key="$1"
    local os="$2"
    local arch="$3"
    local config_file="${TOOLS_CONFIG_FILE:-${SCRIPT_DIR}/tools-config.json}"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error: Configuration file not found${NC}" >&2
        return 1
    fi

    # Get URL pattern and version
    local url_pattern=$(get_tool_property "$tool_key" "url_pattern")
    local version=$(get_tool_property "$tool_key" "version")

    # Get OS and arch mappings
    local mapped_os=$(jq -r ".tools.${tool_key}.os_mapping.${os} // \"${os}\"" "$config_file")
    local mapped_arch=$(jq -r ".tools.${tool_key}.arch_mapping.${arch} // \"${arch}\"" "$config_file")

    # Replace placeholders in URL pattern
    local url="$url_pattern"
    url="${url//\{version\}/$version}"
    url="${url//\{os\}/$mapped_os}"
    url="${url//\{arch\}/$mapped_arch}"

    echo "$url"
}

# Function to get tool version with override support
get_tool_version() {
    local tool_key="$1"
    local env_var_name="${2:-}"

    # Check for environment variable override
    if [ -n "$env_var_name" ] && [ -n "${!env_var_name:-}" ]; then
        echo "${!env_var_name}"
    else
        get_tool_property "$tool_key" "version"
    fi
}

# Function to process annotations with variable substitution
process_annotations() {
    local tool_key="$1"
    local version="$2"
    local config_file="${TOOLS_CONFIG_FILE:-${SCRIPT_DIR}/tools-config.json}"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error: Configuration file not found${NC}" >&2
        return 1
    fi

    # Get annotations and replace {version} placeholder
    jq -r ".tools.${tool_key}.oci_annotations | to_entries | map(\"\(.key)=\(.value | gsub(\"{version}\"; \"${version}\"))\") | .[]" "$config_file"
}

# Export JSON functions
export -f load_tools_config
export -f get_tool_property
export -f get_all_tools
export -f get_artifact_config
export -f build_tool_url
export -f get_tool_version
export -f process_annotations
