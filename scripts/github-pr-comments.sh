#!/bin/bash
#
# github-pr-comment.sh - Creates GitHub PR comments from danger analysis results
# This script is designed to be used in GitHub Actions
#
set -euo pipefail

# Environment variables (should be set by GitHub Actions)
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_PR_NUMBER="${GITHUB_PR_NUMBER:-}"
RESULTS_FILE="${1:-danger-results.json}"

# Colors for output (when not in CI)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    GREEN='\033[0;32m'
    NC='\033[0m'
else
    RED=''
    YELLOW=''
    BLUE=''
    GREEN=''
    NC=''
fi

# Validate inputs
validate_inputs() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo "Error: GITHUB_TOKEN environment variable is not set"
        exit 1
    fi
    
    if [[ -z "$GITHUB_REPOSITORY" ]]; then
        echo "Error: GITHUB_REPOSITORY environment variable is not set"
        exit 1
    fi
    
    if [[ -z "$GITHUB_PR_NUMBER" ]]; then
        echo "Error: GITHUB_PR_NUMBER environment variable is not set"
        exit 1
    fi
    
    if [[ ! -f "$RESULTS_FILE" ]]; then
        echo "Error: Results file not found: $RESULTS_FILE"
        exit 1
    fi
}

# Generate markdown comment from results
generate_comment() {
    local results_json=$(cat "$RESULTS_FILE")
    
    local error_count=$(echo "$results_json" | jq -r '.summary.error_count')
    local warning_count=$(echo "$results_json" | jq -r '.summary.warning_count')
    local info_count=$(echo "$results_json" | jq -r '.summary.info_count')
    local passed=$(echo "$results_json" | jq -r '.summary.passed')
    local timestamp=$(echo "$results_json" | jq -r '.timestamp')
    local commit=$(echo "$results_json" | jq -r '.commit' | cut -c1-7)
    
    # Start building the comment
    local comment="## 🔍 Danger Analysis Report\n\n"
    
    # Add summary header
    if [[ "$passed" == "true" ]]; then
        comment+="### ✅ All checks passed!\n\n"
    else
        comment+="### ❌ Issues found that require attention\n\n"
    fi
    
    # Add summary stats
    comment+="**Summary** (commit \`${commit}\`)\n"
    comment+="- 🔴 **Errors:** ${error_count}\n"
    comment+="- 🟡 **Warnings:** ${warning_count}\n"
    comment+="- 🔵 **Info:** ${info_count}\n\n"
    
    # Add errors section if any
    if [[ "$error_count" -gt 0 ]]; then
        comment+="### ❌ Errors\n\n"
        comment+="These issues must be fixed before merging:\n\n"
        
        local errors=$(echo "$results_json" | jq -c '.results.errors[]')
        while IFS= read -r error; do
            [[ -z "$error" ]] && continue
            
            local rule_name=$(echo "$error" | jq -r '.rule_name')
            local message=$(echo "$error" | jq -r '.message')
            local file=$(echo "$error" | jq -r '.file')
            local line=$(echo "$error" | jq -r '.line')
            local details=$(echo "$error" | jq -r '.details')
            
            comment+="#### 🚫 ${rule_name}\n"
            comment+="${message}\n\n"
            comment+="**File:** \`${file}\`"
            if [[ "$line" != "0" ]]; then
                comment+=" (line ${line})"
            fi
            comment+="\n"
            if [[ "$details" != "null" ]] && [[ -n "$details" ]]; then
                comment+="**Details:** ${details}\n"
            fi
            comment+="\n---\n\n"
        done <<< "$errors"
    fi
    
    # Add warnings section if any
    if [[ "$warning_count" -gt 0 ]]; then
        comment+="### ⚠️ Warnings\n\n"
        comment+="Please review these warnings:\n\n"
        
        local warnings=$(echo "$results_json" | jq -c '.results.warnings[]')
        while IFS= read -r warning; do
            [[ -z "$warning" ]] && continue
            
            local rule_name=$(echo "$warning" | jq -r '.rule_name')
            local message=$(echo "$warning" | jq -r '.message')
            local file=$(echo "$warning" | jq -r '.file')
            local line=$(echo "$warning" | jq -r '.line')
            local details=$(echo "$warning" | jq -r '.details')
            
            comment+="#### ⚠️ ${rule_name}\n"
            comment+="${message}\n\n"
            comment+="**File:** \`${file}\`"
            if [[ "$line" != "0" ]]; then
                comment+=" (line ${line})"
            fi
            comment+="\n"
            if [[ "$details" != "null" ]] && [[ -n "$details" ]]; then
                comment+="**Details:** ${details}\n"
            fi
            comment+="\n---\n\n"
        done <<< "$warnings"
    fi
    
    # Add info section if any
    if [[ "$info_count" -gt 0 ]]; then
        comment+="### ℹ️ Information\n\n"
        comment+="<details>\n"
        comment+="<summary>Click to expand informational messages</summary>\n\n"
        
        local infos=$(echo "$results_json" | jq -c '.results.info[]')
        while IFS= read -r info; do
            [[ -z "$info" ]] && continue
            
            local rule_name=$(echo "$info" | jq -r '.rule_name')
            local message=$(echo "$info" | jq -r '.message')
            local file=$(echo "$info" | jq -r '.file')
            local details=$(echo "$info" | jq -r '.details')
            
            comment+="#### ℹ️ ${rule_name}\n"
            comment+="${message}\n\n"
            comment+="**File:** \`${file}\`\n"
            if [[ "$details" != "null" ]] && [[ -n "$details" ]]; then
                comment+="**Details:** ${details}\n"
            fi
            comment+="\n---\n\n"
        done <<< "$infos"
        
        comment+="</details>\n\n"
    fi
    
    # Add footer
    comment+="---\n"
    comment+="*Generated at ${timestamp} by Danger Bash Analysis*\n"
    comment+="*Rules can be configured in \`danger-bash/rules.json\`*"
    
    echo "$comment"
}

# Find existing comment ID
find_existing_comment() {
    local comments_url="https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${GITHUB_PR_NUMBER}/comments"
    
    # Get all comments and find one that contains our signature
    local comment_id=$(curl -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "$comments_url" | \
        jq -r '.[] | select(.body | contains("🔍 Danger Analysis Report")) | .id' | \
        head -n 1)
    
    echo "${comment_id:-}"
}

# Post or update GitHub comment
post_comment() {
    local comment_body=$1
    local existing_comment_id=$(find_existing_comment)
    
    # Escape the comment for JSON
    local json_body=$(echo "$comment_body" | jq -Rs '.')
    
    if [[ -n "$existing_comment_id" ]]; then
        # Update existing comment
        echo "Updating existing comment (ID: ${existing_comment_id})..."
        
        curl -s -X PATCH \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/comments/${existing_comment_id}" \
            -d "{\"body\": ${json_body}}" > /dev/null
        
        echo "✅ Comment updated successfully"
    else
        # Create new comment
        echo "Creating new comment..."
        
        curl --verbose -s -X POST \
            -H "Authorization: token ${GEN_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${GITHUB_PR_NUMBER}/comments" \
            -d "{\"body\": ${json_body}}" > /dev/null
        
        echo "✅ Comment created successfully"
    fi
}

# Set GitHub Action outputs and exit code
set_github_outputs() {
    local passed=$(jq -r '.summary.passed' "$RESULTS_FILE")
    local error_count=$(jq -r '.summary.error_count' "$RESULTS_FILE")
    local warning_count=$(jq -r '.summary.warning_count' "$RESULTS_FILE")
    
    # Set outputs if in GitHub Actions
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "danger_passed=${passed}" >> "$GITHUB_OUTPUT"
        echo "danger_error_count=${error_count}" >> "$GITHUB_OUTPUT"
        echo "danger_warning_count=${warning_count}" >> "$GITHUB_OUTPUT"
    fi
    
    # Exit with error if checks didn't pass
    if [[ "$passed" == "false" ]]; then
        echo -e "${RED}❌ PR blocked due to danger checks${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ All danger checks passed${NC}"
        exit 0
    fi
}

# Main execution
main() {
    echo "📝 Generating GitHub PR comment from analysis results..."
    
    # Validate inputs
    validate_inputs
    
    # Generate markdown comment
    local comment=$(generate_comment)
    
    # Post comment to GitHub
    post_comment "$comment"
    
    # Set outputs and exit
    set_github_outputs
}

main
