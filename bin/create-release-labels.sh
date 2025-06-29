#!/bin/bash
# Script to create release-please labels using GitHub CLI

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Get repository info
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
if [ -z "$REPO" ]; then
    echo -e "${RED}Error: Could not determine repository${NC}"
    exit 1
fi

echo "Creating release-please labels for repository: $REPO"
echo ""

# Define release-please labels
declare -A labels=(
    ["autorelease: pending"]="ededed"
    ["autorelease: tagged"]="ededed"
    ["autorelease: snapshot"]="ededed"
    ["autorelease: published"]="ededed"
)

# Create each label
for label in "${!labels[@]}"; do
    color="${labels[$label]}"
    echo -n "Creating label '$label'... "
    
    if gh label create "$label" --color "$color" --description "Release Please label" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        # Check if label already exists
        if gh label list --search "$label" | grep -q "$label"; then
            echo -e "${YELLOW}already exists${NC}"
        else
            echo -e "${RED}failed${NC}"
        fi
    fi
done

echo ""
echo -e "${GREEN}Done!${NC} You can now remove 'skip-labeling: true' from the release workflow."