#!/bin/bash
#
# test-locally.sh - Test danger checks locally before pushing
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

# Configuration
DANGER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DANGER_PARENT="$(dirname "$DANGER_DIR")"
RULES_PATH="$(dirname "$DANGER_PARENT")"

BASE_BRANCH="${1:-main}"
INCLUDE_UNCOMMITTED="${INCLUDE_UNCOMMITTED:-true}"

echo -e "${BLUE}🧪 Testing Danger Checks Locally${NC}"
echo "=================================="
echo ""

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Check for uncommitted changes and inform user
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}Uncommitted changes detected${NC}"
    echo "The analysis will include uncommitted changes by default."
    echo ""
fi

# Check if there are any commits ahead of base branch (only if not including uncommitted)
if [[ "$INCLUDE_UNCOMMITTED" != "true" ]]; then
    COMMITS_AHEAD=$(git rev-list --count "${BASE_BRANCH}..HEAD" 2>/dev/null || echo "0")
    if [[ "$COMMITS_AHEAD" -eq 0 ]]; then
        echo -e "${YELLOW}Warning: No commits found ahead of ${BASE_BRANCH}${NC}"
        echo "Make sure you have committed your changes and are on the correct branch."
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
    echo -e "${BLUE}Commits ahead of ${BASE_BRANCH}:${NC} $COMMITS_AHEAD"
fi

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo -e "${BLUE}Current branch:${NC} $CURRENT_BRANCH"
echo -e "${BLUE}Base branch:${NC} $BASE_BRANCH"

if [[ "$INCLUDE_UNCOMMITTED" == "true" ]]; then
    echo -e "${BLUE}Analysis mode:${NC} Including uncommitted changes"
else
    echo -e "${BLUE}Analysis mode:${NC} Committed changes only"
fi
echo ""

# Check if base branch exists
if ! git rev-parse --verify "$BASE_BRANCH" > /dev/null 2>&1; then
    echo -e "${RED}Error: Base branch '$BASE_BRANCH' does not exist${NC}"
    echo "Try fetching from remote: git fetch origin $BASE_BRANCH"
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Please install jq to continue:"
    echo "  macOS: brew install jq"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    echo "  RHEL/CentOS: sudo yum install jq"
    exit 1
fi

# Run the analysis
echo -e "${BLUE}Running danger analysis...${NC}"
echo ""

OUTPUT_FILE="/tmp/danger-results-$(date +%s).json"

ARGS=(
    --rules "${RULES_PATH}/rules.json"
    --output "$OUTPUT_FILE"
    --base "$BASE_BRANCH"
    --verbose
)

if [[ "$INCLUDE_UNCOMMITTED" == "true" ]]; then
    ARGS+=(--include-uncommitted)
fi

if "${DANGER_DIR}/danger-analyze.sh" "${ARGS[@]}"; then
    EXIT_CODE=0
else
    EXIT_CODE=$?
fi

echo ""
echo "=================================="
echo ""

# Show detailed results
if [[ -f "$OUTPUT_FILE" ]]; then
    ERROR_COUNT=$(jq -r '.summary.error_count' "$OUTPUT_FILE")
    WARNING_COUNT=$(jq -r '.summary.warning_count' "$OUTPUT_FILE")
    INFO_COUNT=$(jq -r '.summary.info_count' "$OUTPUT_FILE")
    PASSED=$(jq -r '.summary.passed' "$OUTPUT_FILE")
    
    echo -e "${BLUE}📊 Detailed Results:${NC}"
    echo ""
    
    # Show errors
    if [[ "$ERROR_COUNT" -gt 0 ]]; then
        echo -e "${RED}❌ Errors ($ERROR_COUNT):${NC}"
        jq -r '.results.errors[] | "  • [\(.rule_name)] \(.file): \(.message)"' "$OUTPUT_FILE"
        echo ""
    fi
    
    # Show warnings
    if [[ "$WARNING_COUNT" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Warnings ($WARNING_COUNT):${NC}"
        jq -r '.results.warnings[] | "  • [\(.rule_name)] \(.file): \(.message)"' "$OUTPUT_FILE"
        echo ""
    fi
    
    # Show info
    if [[ "$INFO_COUNT" -gt 0 ]]; then
        echo -e "${BLUE}ℹ️  Information ($INFO_COUNT):${NC}"
        jq -r '.results.infos[] | "  • [\(.rule_name)] \(.file): \(.message)"' "$OUTPUT_FILE"
        echo ""
    fi
    
    echo "=================================="
    echo ""
    
    # Final status
    if [[ "$PASSED" == "true" ]]; then
        echo -e "${GREEN}✅ All checks passed!${NC}"
        echo "Your PR is ready to be submitted."
    else
        echo -e "${RED}❌ Checks failed!${NC}"
    fi
    
    echo ""
    echo "Full results saved to: $OUTPUT_FILE"
else
    echo -e "${RED}Error: Could not read results file${NC}"
fi

exit $EXIT_CODE