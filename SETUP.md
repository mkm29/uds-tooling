# First-Time Setup Guide for UDS k3d Cilium Tools

This guide walks you through setting up everything needed to build and use the UDS k3d Cilium tools.

## Step 1: Install Prerequisites

### ORAS CLI

The `bin/use-tools-artifact.sh` script will auto-install ORAS if not present, or you can install it manually:

**macOS:**

```bash
brew install oras
```

**Linux:**

```bash
curl -LO https://github.com/oras-project/oras/releases/download/v1.2.0/oras_1.2.0_linux_amd64.tar.gz
tar -xzf oras_1.2.0_linux_amd64.tar.gz
sudo mv oras /usr/local/bin/
```

### jq (JSON processor)

**macOS:**

```bash
brew install jq
```

**Linux:**

```bash
# Ubuntu/Debian
sudo apt-get install jq

# RHEL/CentOS
sudo yum install jq
```

## Step 2: Create a GitHub Personal Access Token

1. Go to `https://github.com/settings/tokens/new`
2. Give your token a descriptive name (e.g., "Docker Package Registry")
3. Set an expiration (or select "No expiration" for permanent tokens)
4. Select the following scope:
   - `write:packages` (this automatically selects `read:packages`)
5. Click "Generate token"
6. **Copy the token immediately** (you won't be able to see it again!)

## Step 3: Authenticate to GitHub Container Registry

```bash
# Set your GitHub username
export GITHUB_USERNAME="your-github-username"

# Set your token (paste the token you just created)
export CR_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"

# Login to ghcr.io using ORAS
echo $CR_PAT | oras login ghcr.io -u $GITHUB_USERNAME --password-stdin
```

You should see: `Login Succeeded`

## Step 4: Fork and Clone the Repository

1. Fork the repository on GitHub
2. Clone your fork:

   ```bash
   git clone https://github.com/YOUR_USERNAME/uds-tooling.git
   cd uds-tooling
   ```

## Step 5: Build and Push the Tools Artifact

```bash
# Update the namespace to your GitHub username
NAMESPACE="YOUR_GITHUB_USERNAME" ./bin/build.sh
```

This will:

- Download CLI tools for Linux platforms (amd64 and arm64)
- Create ORAS artifacts with proper file annotations
- Push platform-specific artifacts (e.g., `v1.1.0-linux-amd64`, `v1.1.0-linux-arm64`)

## Step 6: Make the Package Visible

By default, packages pushed from the command line are private and won't show up in your packages list. You have two options:

### Option A: Make the Package Public (Recommended)

1. Go to `https://github.com/YOUR_USERNAME?tab=packages`
2. If you don't see the package, go directly to: `https://github.com/users/YOUR_USERNAME/packages`
3. Click on the `uds-tooling` package
4. Click "Package settings" (gear icon)
5. Scroll down to "Danger Zone"
6. Click "Change visibility" and select "Public"

### Option B: Keep Private but Link to Repository

The package will remain private but will be visible in your packages list if linked to a repository. The ORAS artifact includes the necessary annotation in the manifest.

However, you still need to make it public for others to use it.

## Step 7: Install the Tools Locally

Now you can install the tools using ORAS:

```bash
# Install to ~/.local/bin (ORAS will be auto-installed if needed)
./bin/use-tools-artifact.sh

# Or specify your namespace
NAMESPACE="YOUR_GITHUB_USERNAME" ./bin/use-tools-artifact.sh

# If the package is private, authenticate first
export CR_PAT="YOUR_GITHUB_TOKEN"
./bin/use-tools-artifact.sh
```

The script uses ORAS (OCI Registry As Storage) to pull platform-specific binaries from the container registry.

## Troubleshooting

### "unauthorized: authentication required"

This means you're not logged in. Run:

```bash
echo $CR_PAT | oras login ghcr.io -u $GITHUB_USERNAME --password-stdin
```

### "denied: permission_denied: write_package"

Your token doesn't have the correct permissions. Create a new token with `write:packages` scope.

### "name unknown: repository not found"

Make sure you're using the correct namespace (your GitHub username) and that you've pushed the image.

### Platform Issues

ORAS artifacts are platform-specific. The build script creates separate artifacts for each platform:

- `v1.1.0-linux-amd64` for Linux x86_64
- `v1.1.0-linux-arm64` for Linux ARM64

The `bin/use-tools-artifact.sh` script automatically detects your platform and pulls the correct artifact.

## Next Steps

1. Add the tools directory to your PATH:

   ```bash
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

2. Verify all tools are working:

   ```bash
   uds version
   kubectl version --client
   k3d version
   cilium version
   ```

3. Create your first UDS k3d cluster:

   ```bash
   cd ..  # Back to project root
   uds run deploy
   ```
