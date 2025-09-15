#!/bin/bash
#
# run-danger.sh - Downloads danger core scripts and runs analysis
#
set -euo pipefail

# Configuration
CODEGUARDIAN_VERSION="${CODEGUARDIAN_VERSION:-main}"
CODEGUARDIAN_REPO_NAME="CodeGuardian"
CODEGUARDIAN_REPO="https://github.com/SandeepJy/${CODEGUARDIAN_REPO_NAME}"

CODEGUARDIAN_DIR="CodeGuardian"
SCRIPTS_DIR="$CODEGUARDIAN_DIR/$CODEGUARDIAN_REPO_NAME-${CODEGUARDIAN_VERSION#v}"
SCRIPTS_FULL_PATH="${SCRIPTS_DIR}/scripts"
LOCAL_MODE="${LOCAL_MODE:-true}"
CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_BRANCH="${1:-main}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure we're in the repository root
cd "$(dirname "$0")"

echo -e "${BLUE}🔍 CodeGuardian Analysis Runner${NC}"
echo "=========================="

# Check if CodeGuardian directory exists
if [[ ! -d "$CODEGUARDIAN_DIR" ]]; then
    echo -e "${RED}Error: CodeGuardian directory not found${NC}"
    echo "Please create a 'CodeGuardian' directory with rules.json"
    exit 1
fi

# Check if rules.json exists
if [[ ! -f "$CODEGUARDIAN_DIR/rules.json" ]]; then
    echo -e "${RED}Error: rules.json not found in CodeGuardian directory${NC}"
    exit 1
fi

# Download core scripts if not present or if UPDATE_CODEGUARDIAN is set
if [[ "${LOCAL_MODE}" == "true" ]]; then
    if [[ ! -d "$SCRIPTS_DIR" ]] || [[ "${UPDATE_CODEGUARDIAN:-}" == "true" ]]; then

        # Remove older releases
        echo -e "${BLUE}Cleaning up older CodeGuardian core releases...${NC}"
        find "$CODEGUARDIAN_DIR" -maxdepth 1 -type d -name "CodeGuardian-*" ! -name "${SCRIPTS_DIR##*/}" -exec rm -rf {} +
        echo -e "${GREEN} Cleaned up older releases${NC}"

        echo -e "${BLUE}Downloading CodeGuardian core scripts ${CODEGUARDIAN_VERSION}...${NC}"

        echo -r "${BLUE}Cloning CodeGuardian core scripts from tag ${CODEGUARDIAN_VERSION}...${NC}"
        git clone --depth 1 --branch "$CODEGUARDIAN_VERSION" "$CODEGUARDIAN_REPO" "$SCRIPTS_DIR" || {
            echo -e "${RED}Failed to clone CodeGuardian core scripts${NC}"
            exit 1
        }

        rm -rf "$SCRIPTS_DIR/.git" # Remove .git dir to keep only scripts

        echo -e "${GREEN}Cloned CodeGuardian core scripts${NC}"
    else
        echo -e "${BLUE}Using existing CodeGuardian core scripts{NC}"
    fi
fi

# Make scripts executable
chmod +x "$SCRIPTS_FULL_PATH"/*.sh
chmod +x "$SCRIPTS_FULL_PATH"/lib/*.sh 2>/dev/null || true

# Fetch the base branch to ensure up-to-date comparison
echo -e "${BLUE}Fetching base branch '${BASE_BRANCH}' to ensure up-to-date comparison...${NC}"
git fetch origin "${BASE_BRANCH}" || {
    echo -e "${RED}Failed to fetch base branch '${BASE_BRANCH}'${NC}"
    exit 1
}
echo -e "${GREEN}Base branch fetched successfully.${NC}"

# Run CodeGuardian analysis
echo ""
echo -e "${BLUE}Running CodeGuardian analysis...${NC}"
echo ""

if [[ "${LOCAL_MODE}" == "true" ]]; then
    "$SCRIPTS_FULL_PATH/run-codeguardian-local.sh" ${BASE_BRANCH}
else
    # CI mode
    "${SCRIPTS_FULL_PATH}/codeguardian-analyze.sh" \
        --rules "${CUR_DIR}/${CODEGUARDIAN_DIR}/rules.json" \
        --custom-dir "${CUR_DIR}/${CODEGUARDIAN_DIR}/custom-checks" \
        --output "${CUR_DIR}/${CODEGUARDIAN_DIR}/codeguardian-results.json" \
        --base "${GITHUB_BASE_REF:-main}" \
        --verbose
fi