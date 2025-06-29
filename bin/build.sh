#!/bin/bash
set -euo pipefail

# Script to build and push CLI tools as OCI artifacts using ORAS

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/common.sh
source "${SCRIPT_DIR}/common.sh"

# Load tools configuration
if ! load_tools_config ""; then
    echo "Failed to load tools configuration"
    exit 1
fi

# Configuration from JSON with environment overrides
REGISTRY="${REGISTRY:-$(get_artifact_config 'registry')}"
NAMESPACE="${NAMESPACE:-$(get_artifact_config 'namespace')}"
REPOSITORY="${REPOSITORY:-$(get_artifact_config 'repository')}"
TAG="${TAG:-$(get_artifact_config 'default_tag')}"

# Full artifact name
ARTIFACT="${REGISTRY}/${NAMESPACE}/${REPOSITORY}:${TAG}"

echo "Building ORAS artifact with CLI tools..."
echo "Artifact: ${ARTIFACT}"
echo ""
echo "Tool versions:"

# Display tool versions from config
for tool in $(get_all_tools); do
    tool_name=$(get_tool_property "$tool" "name")
    # Get version with environment variable override support
    env_var_name="$(echo "${tool}_VERSION" | tr '[:lower:]' '[:upper:]')"
    version=$(get_tool_version "$tool" "$env_var_name")
    echo "  ${tool_name}: ${version}"
done
echo ""

# Install ORAS if needed
if ! install_oras ""; then
    exit 1
fi

# Check if required tools are installed
for tool in wget curl tar; do
    if ! command -v $tool &>/dev/null; then
        echo "Error: $tool is required but not installed"
        exit 1
    fi
done

# Check if we're in build-only mode
BUILD_ONLY="${BUILD_ONLY:-false}"

# Check authentication only if not in build-only mode
if [ "$BUILD_ONLY" != "true" ]; then
    if ! oras_login "${REGISTRY}" "${NAMESPACE}"; then
        exit 1
    fi
fi

# Create temporary directory for downloads
TEMP_DIR=$(mktemp -d)
trap 'rm -rf ${TEMP_DIR}' EXIT

# download_with_retry function is already in common.sh

# Function to download tool for specific platform
download_tool() {
    local os=$1
    local arch=$2
    local tool_dir="${TEMP_DIR}/${os}-${arch}"

    echo ""
    echo "=== Downloading tools for ${os}/${arch} ==="
    echo "    Tool directory: ${tool_dir}"

    # Create and verify tool directory
    mkdir -p "${tool_dir}"
    if [ ! -d "${tool_dir}" ]; then
        echo "ERROR: Failed to create directory ${tool_dir}"
        return 1
    fi

    # Download all tools from config
    for tool in $(get_all_tools); do
        local tool_name
        tool_name=$(get_tool_property "$tool" "name")
        local filetype
        filetype=$(get_tool_property "$tool" "filetype")
        local executable_name
        executable_name=$(get_tool_property "$tool" "executable_name")

        # Get version with environment variable override support
        local env_var_name
        env_var_name="$(echo "${tool}_VERSION" | tr '[:lower:]' '[:upper:]')"
        local version
        version=$(get_tool_version "$tool" "$env_var_name")

        echo "  📥 ${tool_name} ${version}..."

        # Build download URL
        local url
        url=$(build_tool_url "$tool" "$os" "$arch")
        echo "  Downloading from: ${url}"

        # Download based on file type
        case "$filetype" in
        "binary")
            if ! download_with_retry "${url}" "${tool_dir}/${executable_name}"; then
                echo "Failed to download ${tool_name}"
                return 1
            fi
            chmod +x "${tool_dir}/${executable_name}"
            ;;
        "tar.gz")
            local temp_tar
            temp_tar="${TEMP_DIR}/${tool}.tar.gz"
            if ! download_with_retry "${url}" "${temp_tar}"; then
                echo "Failed to download ${tool_name}"
                return 1
            fi

            # Handle extraction based on tool configuration
            local extract_path
            extract_path=$(get_tool_property "$tool" "extract_path")
            local extract_files
            extract_files=$(get_tool_property "$tool" "extract_files")

            if [ -n "$extract_path" ]; then
                # Extract to temp dir and move specific file
                local extract_dir
                extract_dir="${TEMP_DIR}/${tool}-extract"
                mkdir -p "${extract_dir}"
                tar -xzf "${temp_tar}" -C "${extract_dir}"

                # Replace placeholders in extract path
                local mapped_os
                mapped_os=$(jq -r ".tools.${tool}.os_mapping.${os} // \"${os}\"" "$TOOLS_CONFIG_FILE")
                local mapped_arch
                mapped_arch=$(jq -r ".tools.${tool}.arch_mapping.${arch} // \"${arch}\"" "$TOOLS_CONFIG_FILE")
                extract_path="${extract_path//\{os\}/$mapped_os}"
                extract_path="${extract_path//\{arch\}/$mapped_arch}"

                mv "${extract_dir}/${extract_path}" "${tool_dir}/${executable_name}"
                rm -rf "${extract_dir}"
            elif [ -n "$extract_files" ]; then
                # Extract specific files directly
                # Use a more portable approach instead of readarray
                local files_to_extract
                files_to_extract=$(jq -r ".tools.${tool}.extract_files[]" "$TOOLS_CONFIG_FILE" | tr '\n' ' ')
                
                # Extract the specified files
                eval "tar -xzf \"${temp_tar}\" -C \"${tool_dir}\" ${files_to_extract}"
            else
                # Extract all files
                tar -xzf "${temp_tar}" -C "${tool_dir}"
            fi

            chmod +x "${tool_dir}/${executable_name}"
            rm -f "${temp_tar}"
            ;;
        *)
            echo "Unknown filetype: $filetype for $tool_name"
            return 1
            ;;
        esac
    done

    echo "  ✅ Downloaded all tools for ${os}/${arch}"
    return 0
}

# Download tools for all platforms
echo ""
echo "📦 Downloading tools for all platforms..."

# Default platforms to build
DEFAULT_PLATFORMS="${PLATFORMS:-linux/amd64,darwin/arm64}"

# Determine platforms to build
if [ -n "${BUILD_OS:-}" ] && [ -n "${BUILD_ARCH:-}" ]; then
    # GitHub Actions single platform build
    echo "Building single platform: ${BUILD_OS}/${BUILD_ARCH}"
    if ! download_tool "${BUILD_OS}" "${BUILD_ARCH}"; then
        echo "Failed to download tools for ${BUILD_OS}/${BUILD_ARCH}"
        exit 1
    fi
else
    # Build all specified platforms
    IFS=',' read -ra PLATFORM_ARRAY <<< "$DEFAULT_PLATFORMS"
    for platform in "${PLATFORM_ARRAY[@]}"; do
        os=$(echo "$platform" | cut -d'/' -f1)
        arch=$(echo "$platform" | cut -d'/' -f2)
        echo "Building platform: ${os}/${arch}"
        if ! download_tool "${os}" "${arch}"; then
            echo "Failed to download tools for ${os}/${arch}"
            exit 1
        fi
    done
fi

echo ""
echo "ℹ️  Note: OCI artifacts now support all platforms including Darwin/macOS"

# This function will be called for each platform
create_platform_manifest_annotations() {
    local os=$1
    local arch=$2
    local output_file=$3

    cat >"${output_file}" <<EOF
{
  "\$manifest": {
    "org.opencontainers.image.title": "UDS k3d Cilium Tools",
    "org.opencontainers.image.description": "CLI tools for UDS k3d Cilium deployment (${os}/${arch})",
    "org.opencontainers.image.version": "${TAG}",
    "org.opencontainers.image.source": "https://github.com/mkm29/uds-tooling",
    "org.opencontainers.image.authors": "UDS k3d Cilium Maintainers",
    "org.opencontainers.image.licenses": "Apache-2.0",
    "org.opencontainers.image.architecture": "${arch}",
    "org.opencontainers.image.os": "${os}"
  }
}
EOF
}

# Push artifacts for each platform
# If in build-only mode, create build directory and prepare artifacts
if [ "$BUILD_ONLY" = "true" ]; then
    echo ""
    echo "📁 Creating build directory structure..."
    
    BUILD_DIR="${BUILD_DIR:-build}"
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    
    # Prepare annotation files for each platform
    for platform_dir in "${TEMP_DIR}"/*-*; do
        if [ -d "$platform_dir" ]; then
            platform=$(basename "$platform_dir")
            os=$(echo "$platform" | cut -d'-' -f1)
            arch=$(echo "$platform" | cut -d'-' -f2)
            
            echo "  Preparing ${platform}..."
            
            # Create platform-specific manifest annotations
            create_platform_manifest_annotations "${os}" "${arch}" "${platform_dir}/manifest-annotations.json"
            
            # Create file annotations for this platform
            echo '{' >"${platform_dir}/file-annotations.json"
            first=true
            for tool in $(get_all_tools); do
                if [ "$first" = false ]; then
                    echo ',' >>"${platform_dir}/file-annotations.json"
                fi
                first=false

                # Get version with environment variable override support
                env_var_name="$(echo "${tool}_VERSION" | tr '[:lower:]' '[:upper:]')"
                version=$(get_tool_version "$tool" "$env_var_name")
                executable_name=$(get_tool_property "$tool" "executable_name")

                echo "  \"${executable_name}\": {" >>"${platform_dir}/file-annotations.json"

                # Process annotations from config
                annotations=$(jq -r ".tools.${tool}.oci_annotations | to_entries | map(\"    \\\"\(.key)\\\": \\\"\(.value | gsub(\"{version}\"; \"${version}\"))\\\"\") | join(\",\\n\")" "$TOOLS_CONFIG_FILE")
                echo "$annotations" >>"${platform_dir}/file-annotations.json"

                echo -n "  }" >>"${platform_dir}/file-annotations.json"
            done
            echo '' >>"${platform_dir}/file-annotations.json"
            echo '}' >>"${platform_dir}/file-annotations.json"
            
            # Create a config.json for this platform
            cat >"${platform_dir}/config.json" <<EOF
{
  "architecture": "${arch}",
  "os": "${os}"
}
EOF
            
            # Copy to build directory
            cp -r "${platform_dir}" "${BUILD_DIR}/"
        fi
    done
    
    echo ""
    echo "✅ Build complete! Artifacts are in ${BUILD_DIR}/"
    echo ""
    echo "Directory structure:"
    ls -la "${BUILD_DIR}"/
    exit 0
fi

echo ""
echo "🚀 Pushing artifacts to registry..."

for platform_dir in "${TEMP_DIR}"/*-*; do
    if [ -d "$platform_dir" ]; then
        platform=$(basename "$platform_dir")
        os=$(echo "$platform" | cut -d'-' -f1)
        arch=$(echo "$platform" | cut -d'-' -f2)

        echo ""
        echo "  📤 Pushing ${os}/${arch}..."

        # Create platform-specific manifest annotations
        create_platform_manifest_annotations "${os}" "${arch}" "${platform_dir}/manifest-annotations.json"

        # Create file annotations for this platform
        echo '{' >"${platform_dir}/file-annotations.json"
        first=true
        for tool in $(get_all_tools); do
            if [ "$first" = false ]; then
                echo ',' >>"${platform_dir}/file-annotations.json"
            fi
            first=false

            # Get version with environment variable override support
            env_var_name="$(echo "${tool}_VERSION" | tr '[:lower:]' '[:upper:]')"
            version=$(get_tool_version "$tool" "$env_var_name")
            executable_name=$(get_tool_property "$tool" "executable_name")

            echo "  \"${executable_name}\": {" >>"${platform_dir}/file-annotations.json"

            # Process annotations from config
            annotations=$(jq -r ".tools.${tool}.oci_annotations | to_entries | map(\"    \\\"\(.key)\\\": \\\"\(.value | gsub(\"{version}\"; \"${version}\"))\\\"\") | join(\",\\n\")" "$TOOLS_CONFIG_FILE")
            echo "$annotations" >>"${platform_dir}/file-annotations.json"

            echo -n "  }" >>"${platform_dir}/file-annotations.json"
        done
        echo '' >>"${platform_dir}/file-annotations.json"
        echo '}' >>"${platform_dir}/file-annotations.json"

        # Push with platform-specific tag
        # Change to the platform directory to avoid absolute path issues
        pushd "${platform_dir}" >/dev/null

        # Create a config.json for this platform
        cat >"config.json" <<EOF
{
  "architecture": "${arch}",
  "os": "${os}"
}
EOF

        # Build oras push command with files and media types from config
        # Use a temporary tag for each platform
        TEMP_TAG="${TAG}-temp-${os}-${arch}-$$"
        push_cmd="oras push \"${REGISTRY}/${NAMESPACE}/${REPOSITORY}:${TEMP_TAG}\""
        push_cmd+=" --artifact-type \"application/vnd.uds.tools.collection.v1\""
        push_cmd+=" --config \"config.json:application/vnd.oci.image.config.v1+json\""
        push_cmd+=" --annotation-file \"file-annotations.json\""
        push_cmd+=" --annotation-file \"manifest-annotations.json\""

        # Add each tool with its media type
        for tool in $(get_all_tools); do
            executable_name=$(get_tool_property "$tool" "executable_name")
            media_type=$(get_tool_property "$tool" "media_type")
            push_cmd+=" \"${executable_name}:${media_type}\""
        done

        if ! eval "$push_cmd"; then
            popd >/dev/null
            echo "  ❌ Failed to push ${os}/${arch}"
            exit 1
        fi

        popd >/dev/null
        echo "  ✅ Pushed ${os}/${arch}"
    fi
done

# Collect all temporary platform tags
echo ""
echo "📋 Creating multi-platform manifest..."
TEMP_TAGS=()
TEMP_TAG_NAMES=()
for platform_dir in "${TEMP_DIR}"/*-*; do
    if [ -d "$platform_dir" ]; then
        platform=$(basename "$platform_dir")
        os=$(echo "$platform" | cut -d'-' -f1)
        arch=$(echo "$platform" | cut -d'-' -f2)
        TEMP_TAG="${TAG}-temp-${os}-${arch}-$$"
        TEMP_TAGS+=("${REGISTRY}/${NAMESPACE}/${REPOSITORY}:${TEMP_TAG}")
        TEMP_TAG_NAMES+=("${TEMP_TAG}")
        echo "  ✓ Pushed ${os}/${arch} (temporary tag: ${TEMP_TAG})"
    fi
done

# Create manifest index with the final tag
if [ "${#TEMP_TAGS[@]}" -gt 0 ] && [ "$BUILD_ONLY" != "true" ]; then
    echo ""
    echo "🔗 Creating unified multi-platform manifest..."
    
    # First check if this version of ORAS supports manifest index
    if oras manifest index --help &>/dev/null 2>&1; then
        # Create the index with the final tag
        # Note: ORAS v1.3.0-beta.3 automatically pushes the index when created
        # The command expects: oras manifest index create <target> <source-tags>...
        if oras manifest index create "${ARTIFACT}" "${TEMP_TAG_NAMES[@]}" \
            --annotation "org.opencontainers.image.title=UDS k3d Cilium Tools" \
            --annotation "org.opencontainers.image.description=CLI tools for UDS k3d Cilium deployment (multi-platform)" \
            --annotation "org.opencontainers.image.version=${TAG}" \
            --annotation "org.opencontainers.image.source=https://github.com/mkm29/uds-tooling" \
            --annotation "org.opencontainers.artifact.created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"; then
            
            echo "  ✅ Created and pushed multi-platform manifest: ${ARTIFACT}"
            
            # Clean up temporary tags
            echo ""
            echo "🧹 Cleaning up temporary tags..."
            for i in "${!TEMP_TAG_NAMES[@]}"; do
                if oras manifest delete "${REGISTRY}/${NAMESPACE}/${REPOSITORY}:${TEMP_TAG_NAMES[$i]}" --force &>/dev/null; then
                    echo "  ✓ Deleted temporary tag: ${TEMP_TAG_NAMES[$i]}"
                else
                    echo "  ⚠️  Failed to delete temporary tag: ${TEMP_TAG_NAMES[$i]}"
                fi
            done
        else
            echo "  ❌ Failed to create manifest index"
            exit 1
        fi
    else
        echo "  ⚠️  Warning: Your version of ORAS doesn't support manifest index creation"
        echo "  ℹ️  Falling back to platform-specific tags"
        # If manifest index is not supported, create platform-specific tags from temp tags
        for i in "${!TEMP_TAGS[@]}"; do
            # Extract platform from the temp tag name
            temp_tag="${TEMP_TAG_NAMES[$i]}"
            # Format: v1.0.0-temp-linux-amd64-12345
            # Extract the platform part (linux-amd64)
            platform=$(echo "$temp_tag" | sed -E 's/.*-temp-(.*)-[0-9]+$/\1/')
            
            # Copy manifest from temp tag to platform-specific tag
            echo "  Creating platform-specific tag: ${ARTIFACT}-${platform}"
            oras manifest fetch "${TEMP_TAGS[$i]}" | \
                oras manifest push "${ARTIFACT}-${platform}"
        done
    fi
fi

echo ""
echo "✅ Successfully built and pushed ORAS artifacts!"
echo ""
echo "Single multi-platform artifact created:"
echo "  ${ARTIFACT}"
echo ""
echo "To use the tools (specify platform):"
echo "  oras pull ${ARTIFACT} --platform linux/amd64"
echo "  oras pull ${ARTIFACT} --platform darwin/arm64"
echo ""
echo "Or use the installer script:"
echo "  ./bin/use-tools-artifact.sh"
