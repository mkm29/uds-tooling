# UDS Tools OCI Artifact

This repository provides scripts to create and distribute OCI artifacts that bundle CLI tools required for UDS (Unicorn Delivery Service) deployments.
The tools are configured via a central JSON file for easy version management and extensibility.

📚 **First time?** See the [First-Time Setup Guide](SETUP.md) for detailed instructions.

## What's Included

The OCI artifact contains the following tools (configured in `tools-config.json`):

- **UDS CLI** (v0.27.7): Defense Unicorns UDS CLI
- **Helm** (v3.18.3): Kubernetes package manager
- **Cilium CLI** (v0.18.4): Cilium CNI management tool
- **Hubble CLI** (v1.17.5): Hubble observability CLI for network flows
- **k3d** (v5.8.3): Lightweight Kubernetes in Docker
- **kubectl** (v1.33.2): Kubernetes command-line tool
- **k9s** (v0.50.6): Terminal-based Kubernetes UI

Tool versions and metadata are centrally managed in the `tools-config.json` file.

> **Note**: All scripts have been moved to the `bin/` directory for better organization. If you have existing scripts or CI/CD pipelines, update paths from `./script.sh` to `./bin/script.sh`.

## Prerequisites

- Access to a container registry (e.g., GitHub Container Registry)
- Authentication to your registry (see [Authentication](#authentication) section)
- ORAS CLI for building and pulling artifacts (auto-installed by installer script)
- `jq` for JSON parsing (auto-installed by installer script)
  - **Note**: The one-line installer (`install.sh`) will check for ORAS and jq and offer to install them automatically:
- macOS: Uses Homebrew to install dependencies
- Linux: Downloads binaries from GitHub releases
- All tools are installed to `$HOME/.local/bin` (no sudo required)
- The installer will remind you to add `$HOME/.local/bin` to your PATH if needed

## Authentication

### GitHub Container Registry (ghcr.io)

1. **Create a Personal Access Token (PAT)**:
   - Go to `https://github.com/settings/tokens/new`
   - Select scope: `write:packages` (this automatically includes `read:packages`)
   - Copy the generated token

2. **Login to ghcr.io**:

   ```bash
   export CR_PAT=YOUR_TOKEN_HERE
   echo $CR_PAT | oras login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
   ```

3. **Verify authentication**:

   ```bash
   oras manifest fetch ghcr.io/YOUR_USERNAME/test:latest
   ```

For more details, see the [official GitHub documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

## Building the Tools Artifact

### Build ORAS Artifact (Native OCI artifacts - Linux only)

```bash
# Build and push as ORAS artifacts (Linux platforms only)
./bin/build.sh

# Build only (no push) - useful for testing
BUILD_ONLY=true ./bin/build.sh

# Or with custom settings
REGISTRY=ghcr.io \
NAMESPACE=myusername \
REPOSITORY=uds-tools-oras \
TAG=v1.1.0 \
./bin/build.sh

# Override tool versions
UDS_VERSION=v0.27.7 \
HELM_VERSION=v3.18.3 \
CILIUM_CLI_VERSION=v0.18.4 \
./bin/build.sh

# Build single platform for CI/CD
BUILD_OS=linux BUILD_ARCH=amd64 BUILD_ONLY=true ./bin/build.sh

# Build for additional platforms (e.g., linux/arm64, darwin/amd64)
PLATFORMS="linux/amd64,linux/arm64,darwin/amd64,darwin/arm64" ./bin/build.sh
```

This creates proper OCI artifacts with file annotations that ORAS can pull directly.
**Note**:

- ORAS artifacts support all platforms; default build includes linux/amd64 and darwin/arm64
- All platforms are combined into a single multi-platform manifest index
- Only one tag is used (e.g., `v1.0.1`) but requires platform specification when pulling
- The artifactType is set to `application/vnd.uds.tools.collection.v1` for proper artifact identification
- **Important**: When pulling manually with `oras pull`, you must specify the `--platform` flag to avoid filename conflicts

## Using the Tools

### Quick Install

```bash
# One-line install (auto-detects OS and architecture)
# This will check for and optionally install dependencies (oras and jq)
curl -sL https://raw.githubusercontent.com/mkm29/uds-tooling/main/bin/install.sh | bash

# Download and install tools to $HOME/.local/bin
./bin/use-tools-artifact.sh

# Force reinstall even if tools are already installed
./bin/use-tools-artifact.sh --force

# Or specify custom location (requires sudo for system directories)
sudo INSTALL_PATH=$HOME/.local/bin ./bin/use-tools-artifact.sh

# With authentication (if private)
export CR_PAT=YOUR_GITHUB_TOKEN
./bin/use-tools-artifact.sh

# Show help and options
./bin/use-tools-artifact.sh --help
```

#### Example Output

When tools are already installed:

```bash
🔧 Installing tools to /home/user/.local/bin...
  ⚠ UDS CLI already installed: uds-cli v0.27.7
     Skipping installation. Use --force to override.
  ⚠ Helm already installed: version.BuildInfo{Version:"v3.18.3"}
     Skipping installation. Use --force to override.
  ✓ Cilium CLI installed to /home/user/.local/bin
  ✓ Hubble CLI installed to /home/user/.local/bin
```

With verification showing installation paths:

```bash
🔍 Verifying installations...
  UDS CLI: v0.27.7 ($HOME/.local/bin/uds)
  Helm: v3.18.3 ($HOME/.local/bin/helm)
  Cilium CLI: cilium-cli v0.18.4 (/home/user/.local/bin/cilium)
  Hubble CLI: hubble v1.17.5 (/home/user/.local/bin/hubble)
```

The installer:

- Checks for required dependencies (ORAS CLI and jq) and offers to install them
- Automatically detects your platform using `uname -s` and `uname -m`
- For macOS: Uses Homebrew to install dependencies
- For Linux: Downloads binaries directly from GitHub releases
- Installs all dependencies to `$HOME/.local/bin` (no sudo required)
- Temporarily adds `$HOME/.local/bin` to PATH for the current session
- Downloads all required scripts (common.sh, tools-config.json, use-tools-artifact.sh)
- Checks if tools are already installed system-wide before installing
- Skips installation of existing tools (use `--force` to override)
- Uses the `install` command for proper permissions (755) when available
- Shows the installation path for each tool during verification
- Displays a reminder to permanently add `$HOME/.local/bin` to `PATH` if needed

### PATH Configuration

If `$HOME/.local/bin` is not in your `PATH`, add it to your shell configuration:

```bash
# For bash (~/.bashrc)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# For zsh (~/.zshrc)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# For fish (~/.config/fish/config.fish)
echo 'set -gx PATH $HOME/.local/bin $PATH' >> ~/.config/fish/config.fish
source ~/.config/fish/config.fish
```

### Manual Usage with ORAS

```bash
# Install ORAS if not present
brew install oras  # macOS with Homebrew

# Or manually download for Linux
ORAS_VERSION="1.3.0-beta.3"  # Required for manifest index support
curl -LO "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz"
mkdir -p $HOME/.local/bin
tar -xzf oras_${ORAS_VERSION}_linux_amd64.tar.gz -C $HOME/.local/bin oras
chmod +x $HOME/.local/bin/oras

# Login to registry (if private)
echo $CR_PAT | oras login ghcr.io -u YOUR_USERNAME --password-stdin

# Pull the artifact - MUST specify platform to avoid filename conflicts
# For Linux AMD64:
oras pull ghcr.io/mkm29/uds-tooling/tools:v1.0.1 --platform linux/amd64 -o ./tools-bin

# For macOS Apple Silicon:
oras pull ghcr.io/mkm29/uds-tooling/tools:v1.0.1 --platform darwin/arm64 -o ./tools-bin

# Or auto-detect your platform:
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
oras pull ghcr.io/mkm29/uds-tooling/tools:v1.0.1 --platform ${PLATFORM} -o ./tools-bin

# Tools will be extracted directly (no subdirectories)
chmod +x ./tools-bin/*
./tools-bin/uds version

# Or install system-wide
sudo cp tools-bin/* /usr/local/bin/
```

#### Understanding Multi-Platform Manifests

This project uses OCI manifest indexes (multi-platform manifests) to support multiple platforms with a single tag. When pulling:

- **Always specify `--platform`**: Without it, ORAS may attempt to pull all platforms, causing filename conflicts
- **Platform format**: Use `os/architecture` format (e.g., `linux/amd64`, `darwin/arm64`)
- **Automatic detection**: The installer script (`use-tools-artifact.sh`) handles platform detection automatically

## CI/CD Integration

### GitHub Actions Workflows

This repository includes GitHub Actions workflows optimized for protected branches:

1. **Build and Test** (`build-and-test.yml`): Runs on PRs and merge groups
   - Builds artifacts for all platforms without pushing
   - Tests executables
   - Validates JSON configuration
   - Runs ShellCheck on scripts

2. **Release Artifacts** (`release-artifacts.yml`): Runs on version tags or manual dispatch
   - Builds and pushes OCI artifacts to GitHub Container Registry  
   - Supports custom tags for manual releases
   - Creates platform-specific artifacts

3. **Release Please** (`release.yml`): Manages versioning and changelogs
   - Creates release PRs with version bumps
   - Updates changelog automatically
   - Triggers artifact builds on release creation

4. **CI** (`ci.yml`): Continuous integration checks
   - Lints shell scripts and Markdown files
   - Tests common functions
   - Runs security scans

5. **Update Tool Versions** (`update-tools.yml`): Automated dependency updates
   - Runs weekly to check for new tool versions
   - Creates PRs with version updates

### Protected Branch Support

The workflows are designed to work with protected main branches:

- PRs are tested without pushing artifacts
- Only tagged releases or manual dispatches trigger artifact pushes
- All changes go through PR review process
- Automated tool updates create PRs for review

### Required Repository Settings

For the release-please and update-tools workflows to create PRs:

1. **Allow GitHub Actions to create PRs** (Required):
   - Go to Settings → Actions → General
   - Under "Workflow permissions", check "Allow GitHub Actions to create and approve pull requests"

### Enabling Release Labels (Optional)

The release workflow currently skips label creation due to GitHub token limitations. The default `GITHUB_TOKEN` cannot manage labels on pull requests.

To enable automatic labeling, you must use one of these options:

#### Option 1: Use a Personal Access Token (Recommended)

1. Create a PAT with full `repo` scope at [https://github.com/settings/tokens](https://github.com/settings/tokens)
2. Add it as a repository secret named `RELEASE_PLEASE_TOKEN`
3. Update `.github/workflows/release.yml`:

   ```yaml
   token: ${{ secrets.RELEASE_PLEASE_TOKEN }}
   # Remove skip-labeling: true
   ```

#### Option 2: Use GitHub App

Create a GitHub App with label and pull request permissions, then use its token.

**Note**: Pre-creating labels with `./bin/create-release-labels.sh` is not sufficient because the token still needs permission to add/remove labels from PRs, which the default `GITHUB_TOKEN` lacks.

### GitHub Actions Example

```yaml
- name: Set up ORAS
  uses: oras-project/setup-oras@v1
  with:
    version: 1.3.0-beta.3  # Required for manifest index support

- name: Extract UDS Tools
  run: |
    oras pull ghcr.io/mkm29/uds-tooling/tools:v1.0.1 --platform linux/amd64 -o /tmp/tools
    sudo cp /tmp/tools/* $HOME/.local/bin/
    sudo chmod +x $HOME/.local/bin/*
- name: Verify Tools
  run: |
    uds version
    helm version
    cilium version
    hubble version
    k3d version
    kubectl version --client
    k9s version
```

### GitLab CI Example

```yaml
install-tools:
  image: alpine:latest
  script:
    - apk add curl tar
    - curl -LO https://github.com/oras-project/oras/releases/download/v1.3.0-beta.3/oras_1.3.0-beta.3_linux_amd64.tar.gz
    - tar -xzf oras_1.3.0-beta.3_linux_amd64.tar.gz
    - mv oras $HOME/.local/bin/
    - oras pull ghcr.io/mkm29/uds-tooling/tools:v1.0.1 --platform linux/amd64 -o /tmp/tools
    - cp /tmp/tools/* $HOME/.local/bin/
    - chmod +x $HOME/.local/bin/*
    - uds version && helm version && cilium version && hubble version && k3d version && kubectl version --client && k9s version
```

## Making Your Package Visible

### Make the Package Public (Recommended)

After your first push, the package will be private. To make it public:

1. Go to `https://github.com/users/YOUR_USERNAME/packages`
2. Click on the `uds-tooling` package
3. Click "Package settings" (gear icon)
4. Scroll down to "Danger Zone"
5. Click "Change visibility" and select "Public"

The package will be automatically linked to your repository if the ORAS manifest includes the proper annotation:

```json
{
  "annotations": {
    "org.opencontainers.image.source": "https://github.com/YOUR_USERNAME/uds-tooling"
  }
}
```

## Configuration

### Tool Configuration (tools-config.json)

All tools are configured in the `tools-config.json` file, which defines:

- Tool metadata (name, version, description)
- Download URL patterns with OS/architecture placeholders
- File types (binary vs tar.gz)
- OS/architecture mappings for different naming conventions
- OCI annotations and media types
- Artifact registry settings

#### Configuration Structure

```json
{
  "tools": {
    "uds": {
      "name": "UDS CLI",
      "version": "v0.27.7",
      "description": "UDS (Unicorn Delivery Service) CLI",
      "url_pattern": "https://github.com/defenseunicorns/uds-cli/releases/download/{version}/uds-cli_{version}_{os}_{arch}",
      "filetype": "binary",
      "os_mapping": {
        "darwin": "Darwin",
        "linux": "Linux"
      },
      "executable_name": "uds",
      "oci_annotations": {...},
      "media_type": "application/vnd.uds.cli"
    },
    // ... other tools
  },
  "artifact": {
    "registry": "ghcr.io",
    "namespace": "mkm29",
    "repository": "uds-tooling",
    "default_tag": "v1.0.0"
  }
}
```

### Custom Tool Versions

You can override tool versions in two ways:

1. **Environment Variables** (takes precedence):

   ```bash
   # Override specific tool versions when building
   UDS_VERSION=v0.27.7 \
   HELM_VERSION=v3.18.3 \
   CILIUM_CLI_VERSION=v0.18.4 \
   ./bin/build.sh
   ```

2. **Edit tools-config.json**:

   ```bash
   # Edit the configuration file
   vim tools-config.json
   # Update the version field for any tool
   ```

### Adding or Removing Tools

To add a new tool or remove an existing one, edit the `tools-config.json` file:

```json
{
  "tools": {
    "newtool": {
      "name": "New Tool",
      "version": "v1.1.0",
      "description": "Description of the new tool",
      "url_pattern": "https://example.com/releases/{version}/{os}-{arch}/newtool",
      "filetype": "binary",
      "os_mapping": {
        "darwin": "darwin",
        "linux": "linux"
      },
      "arch_mapping": {
        "amd64": "amd64",
        "arm64": "arm64"
      },
      "executable_name": "newtool",
      "oci_annotations": {
        "org.opencontainers.image.title": "newtool",
        "org.opencontainers.image.description": "New Tool {version}"
      },
      "media_type": "application/vnd.newtool.cli"
    }
  }
}
```

### Private Registry

```bash
# Push to private registry
REGISTRY=my-registry.company.com \
NAMESPACE=platform-team \
REGISTRY_USERNAME=svcaccount \
REGISTRY_PASSWORD="${REGISTRY_TOKEN}" \
./bin/build.sh
```

## ORAS Artifact Details

### ORAS Artifact (`build.sh`)

- Creates OCI artifacts with proper file annotations
- Multi-platform support (default: linux/amd64, darwin/arm64; configurable for other platforms)
- Each binary is a separate layer with metadata
- Uses OCI manifest indexes for multi-platform support
- Best for direct file distribution across all platforms
- All platforms are combined into a single multi-platform manifest index
- Only one tag is used (e.g., `v1.0.1`) with explicit platform selection via `--platform` flag
- Requires ORAS v1.3.0+ for manifest index creation

## Contributing

### Commit Message Format

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automated versioning and changelog generation. Please format your commits as:

```bash
<type>(<scope>): <subject>
```

Types:

- `feat`: New features (bumps minor version)
- `fix`: Bug fixes (bumps patch version)
- `docs`: Documentation changes
- `chore`: Maintenance tasks
- `ci`: CI/CD changes
- `test`: Test additions or changes
- `refactor`: Code refactoring

Example: `feat(tools): add new CLI tool to bundle`

## Repository Structure

```bash
.
├── bin/                           # All executable scripts
│   ├── build.sh                   # Build ORAS artifact with CLI tools
│   ├── use-tools-artifact.sh      # Install tools from ORAS artifacts
│   ├── common.sh                  # Shared functions and JSON parsing utilities
│   └── install.sh                 # Quick installer script
├── .github/
│   └── workflows/                 # GitHub Actions workflows
│       ├── build-and-test.yml     # PR testing workflow
│       ├── release-artifacts.yml  # Artifact release workflow
│       ├── release.yml            # Release-please automation
│       ├── ci.yml                 # Continuous integration checks
│       └── update-tools.yml       # Automated tool version updates
├── tools-config.json              # Central configuration for all tools
├── .markdownlint.json             # Markdown linting configuration
├── release-please-config.json     # Release automation configuration
├── .release-please-manifest.json  # Version tracking
├── CHANGELOG.md                   # Project changelog
├── README.md                      # This documentation
└── SETUP.md                       # First-time setup guide
```

## Artifact Structure

```bash
.
├── bin/
│   ├── uds         # UDS CLI binary
│   ├── helm        # Helm binary
│   ├── cilium      # Cilium CLI binary
│   ├── hubble      # Hubble CLI binary
│   ├── k3d         # k3d binary
│   ├── kubectl     # Kubernetes CLI binary
│   └── k9s         # Terminal Kubernetes UI binary
├── manifest.json   # Artifact metadata
└── README.md       # Artifact documentation
```

## Benefits

1. **Single Source of Truth**: All required tools in one versioned artifact
2. **Multi-Platform Support**: Works on Linux and macOS (amd64 and arm64)
3. **CI/CD Friendly**: Easy to integrate into pipelines
4. **Version Control**: Pin specific versions of all tools
5. **Fast Downloads**: Binary distribution, no compilation needed
6. **Registry Agnostic**: Works with any OCI-compliant registry
7. **JSON Configuration**: Centralized tool management with `tools-config.json`
8. **Flexible Updates**: Easy to add, remove, or update tools by editing JSON
9. **Environment Overrides**: Support for version overrides via environment variables
10. **Smart Installation**: Detects existing tools and skips unnecessary installs
11. **Proper Permissions**: Uses `install` command for correct file permissions (755)
12. **Force Option**: Override existing installations with `--force` flag
13. **No Sudo Required**: All tools install to `$HOME/.local/bin` in user space
14. **Dependency Management**: Auto-installs ORAS and jq if missing
15. **PATH Guidance**: Provides clear instructions for PATH configuration

## Troubleshooting

### Registry Authentication Issues

```bash
# Login to GitHub Container Registry
echo $CR_PAT | oras login ghcr.io -u USERNAME --password-stdin
```

### ORAS Issues

```bash
# ORAS not found
# The use-tools-artifact.sh script will auto-install it, or:
brew install oras  # macOS
# or download from https://github.com/oras-project/oras/releases

# Platform selection issues
# IMPORTANT: Always specify --platform when pulling multi-platform manifests
oras pull ghcr.io/mkm29/uds-tooling/tools:v1.1.0 --platform linux/amd64 -o ./tools

# List available platforms in the manifest index
oras manifest fetch ghcr.io/mkm29/uds-tooling/tools:v1.1.0 | jq '.manifests[].platform'

# "duplicate name" error fix
# This error occurs when pulling without --platform flag
# Wrong: oras pull ghcr.io/mkm29/uds-tooling/tools:v1.1.0 -o ./tools
# Right: oras pull ghcr.io/mkm29/uds-tooling/tools:v1.1.0 --platform darwin/arm64 -o ./tools
```

### JSON Configuration Issues

```bash
# jq not found
brew install jq  # macOS
apt-get install jq  # Ubuntu/Debian
yum install jq  # RHEL/CentOS

# Validate JSON configuration
jq empty tools-config.json

# List all configured tools
jq '.tools | keys[]' tools-config.json

# Check tool version
jq '.tools.uds.version' tools-config.json
```

### Wrong Platform

The scripts automatically detect and download the correct platform. If you need specific platforms:

```bash
# Download specific platform
PLATFORMS=darwin/arm64 ./bin/build.sh

# Multiple platforms
PLATFORMS="linux/amd64,darwin/arm64" ./bin/build.sh
```
