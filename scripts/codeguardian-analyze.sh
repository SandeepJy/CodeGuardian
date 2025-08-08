#!/bin/bash
#
# danger-analyze.sh - Main analyzer script for checking git diffs against rules
# This script replaces the CodeGuardian JS functionality with pure bash
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT_ROOT="${SCRIPT_DIR}/.."
REPO_ROOT="$(cd "${PROJECT_ROOT}/.." && pwd)"
RULES_FILE="${RULES_FILE:-${PROJECT_ROOT}/rules.json}"
CUSTOM_DIR="${CUSTOM_DIR:-${PROJECT_ROOT}/custom-checks}"
OUTPUT_FILE="${OUTPUT_FILE:-${PROJECT_ROOT}/codeguardian-results.json}"
BASE_BRANCH="${BASE_BRANCH:-main}"
VERBOSE="${VERBOSE:-false}"

# Source utilities
source "${SCRIPT_DIR}/lib/utils.sh"

# Expose helper functions for custom scripts
export -f log
export VERBOSE

# Counters
errors=0
warnings=0
info=0
results=()

# Get the target branch (where we're merging to)
get_target_branch() {
    if [[ -n "${BASE_BRANCH}" ]]; then
        echo "${BASE_BRANCH}"
        return
    fi
    
    # Try to detect from CI environment
    if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
        echo "${GITHUB_BASE_REF}"
        return
    fi
    
    # Default to BASE_BRANCH
    echo "${BASE_BRANCH}"
}
export -f get_target_branch

# Get the source branch (what we're merging from)
get_source_branch() {
    # Try to get current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    
    # In CI, might need to use GITHUB_HEAD_REF
    if [[ -z "$current_branch" || "$current_branch" == "HEAD" ]]; then
        if [[ -n "${GITHUB_HEAD_REF:-}" ]]; then
            current_branch="${GITHUB_HEAD_REF}"
        fi
    fi
    
    echo "$current_branch"
}
export -f get_source_branch

# Helper function to get base ref with GitHub Actions support
get_base_ref() {
    local base_ref="${BASE_BRANCH}"

    log "DEBUG" "Sandeep base ref is $BASE_BRANCH"
    
    # If already has origin/ prefix, use as-is
    if [[ "$base_ref" == origin/* ]]; then
        echo "$base_ref"
        return
    fi
    
    # Always try to use remote branch for consistency
    local remote_ref="origin/$base_ref"
    
    # Check if remote branch exists
    if git rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
        echo "$remote_ref"
        return
    fi
    
    # If remote doesn't exist, try to fetch it
    log "INFO" "Remote branch $remote_ref not found, attempting to fetch..."
    if git fetch origin "$base_ref:$base_ref" >/dev/null 2>&1; then
        echo "$remote_ref"
        return
    fi
    
    # If fetch fails, try local branch as fallback
    if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
        log "WARN" "Using local branch $base_ref instead of remote"
        echo "$base_ref"
        return
    fi
    
    # Last resort - return the original and let git show the error
    log "ERROR" "Neither remote nor local branch found for $base_ref"
    echo "$base_ref"
}
export -f get_base_ref

# Get untracked files
get_untracked_files() {
    git ls-files --others --exclude-standard 2>/dev/null || echo ""
}
export -f get_untracked_files

# Get files that were deleted
get_deleted_files() {
    local base_ref=$(get_base_ref)
    
    local deleted_files=""
    
    # Get committed deleted files
    deleted_files=$(git diff --name-only --diff-filter=D "${base_ref}...HEAD" 2>/dev/null || echo "")
    # Get uncommitted deleted files (staged)
    local staged_deleted=$(git diff --name-only --diff-filter=D --cached 2>/dev/null || echo "")
    # Get uncommitted deleted files (unstaged)
    local unstaged_deleted=$(git diff --name-only --diff-filter=D HEAD 2>/dev/null || echo "")
    
    # Combine and deduplicate
    local all_deleted=$(printf "%s\n%s\n%s" "$deleted_files" "$staged_deleted" "$unstaged_deleted" | sort -u | grep -v '^$' || echo "")
    echo "$all_deleted"
}
export -f get_deleted_files

# Get all changed files (excluding deleted)
get_changed_files() {
    local base_ref=$(get_base_ref)
    
    local changed_files=""
    
    if is_running_in_ci; then
        # In CI, use three dots to get changes from merge base
        changed_files=$(git diff --name-only "${base_ref}...HEAD" 2>/dev/null || echo "")
    else
        # Locally, use two dots to compare directly
        # This gets all changes from base_ref to current working tree
        changed_files=$(git diff --name-only "${base_ref}" 2>/dev/null || echo "")
        
        # Also get untracked files
        local untracked_files=$(get_untracked_files)
        
        # Combine and deduplicate
        local all_files=$(printf "%s\n%s" "$changed_files" "$untracked_files" | sort -u | grep -v '^$' || echo "")
        
        # Filter out deleted files
        local deleted_files=$(get_deleted_files)
        if [[ -n "$deleted_files" ]]; then
            all_files=$(comm -23 <(echo "$all_files" | sort) <(echo "$deleted_files" | sort) | grep -v '^$' || echo "")
        fi
        
        echo "$all_files"
    fi
}
export -f get_changed_files

get_added_files() {
    local base_ref=$(get_base_ref)
    
    if is_running_in_ci; then
        # In CI, use the standard git diff approach
        local added_files=""
        
        # Get committed added files
        added_files=$(git diff --name-only --diff-filter=A "${base_ref}...HEAD" 2>/dev/null || echo "")
        echo "$added_files"
    else
        # Locally, check actual current state
        local added_files=""
        
        # Get files that don't exist in base but exist now
        local all_current_files=$(git ls-files)
        local base_files=$(git ls-tree -r "${base_ref}" --name-only 2>/dev/null || echo "")
        
        # Find files that exist now but not in base
        added_files=$(comm -13 <(echo "$base_files" | sort) <(echo "$all_current_files" | sort) | grep -v '^$' || echo "")
        
        # Add untracked files
        local untracked_files=$(get_untracked_files)
        
        # Combine and deduplicate
        local all_added=$(printf "%s\n%s" "$added_files" "$untracked_files" | sort -u | grep -v '^$' || echo "")
        
        # Filter out files that don't currently exist
        local existing_added=""
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            [[ -f "$file" ]] && existing_added="${existing_added}${file}"$'\n'
        done <<< "$all_added"
        
        echo "$existing_added" | grep -v '^$' || echo ""
    fi
}
export -f get_added_files

get_modified_files() {
    local base_ref=$(get_base_ref)
    
    local modified_files=""
    
    # Get committed modified files
    modified_files=$(git diff --name-only --diff-filter=M "${base_ref}...HEAD" 2>/dev/null || echo "")
    # Get uncommitted modified files
    local uncommitted_modified=$(git diff --name-only --diff-filter=M HEAD 2>/dev/null || echo "")
    local staged_modified=$(git diff --name-only --diff-filter=M --cached 2>/dev/null || echo "")
    
    # Combine and deduplicate
    local all_modified=$(printf "%s\n%s\n%s" "$modified_files" "$uncommitted_modified" "$staged_modified" | sort -u | grep -v '^$' || echo "")
    echo "$all_modified"
}
export -f get_modified_files

# Check if a file is untracked
is_untracked_file() {
    local file="$1"
    local untracked_files=$(get_untracked_files)
    
    if [[ -n "$untracked_files" ]]; then
        while IFS= read -r untracked; do
            [[ "$file" == "$untracked" ]] && return 0
        done <<< "$untracked_files"
    fi
    
    return 1
}
export -f is_untracked_file

# Add a function to detect if we're running in CI
is_running_in_ci() {
    # GitHub Actions sets GITHUB_ACTIONS=true
    [[ "${GITHUB_ACTIONS:-false}" == "true" ]] || [[ "${CI:-false}" == "true" ]]
}
export -f is_running_in_ci

# Get added lines for a file with line numbers
get_added_lines_with_numbers() {
    local file="$1"
    local base_ref=$(get_base_ref)
    
    # Check if file exists (it might be deleted)
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    
    # Check if this is an untracked file
    if is_untracked_file "$file"; then
        # For untracked files, all lines are "added"
        local line_num=1
        while IFS= read -r line; do
            echo "${line_num}:${line}"
            ((line_num++))
        done < "$file"
        return 0
    fi
    
    local diff_output=""
    
    if is_running_in_ci; then
        # In CI, analyze commits between base and HEAD
        diff_output=$(git diff "${base_ref}...HEAD" -- "$file" 2>/dev/null || true)
    else
        # Locally, analyze the current working tree state vs base
        # This shows what would be in the PR if you pushed right now
        diff_output=$(git diff "${base_ref}" -- "$file" 2>/dev/null || true)
    fi
    
    if [[ -z "$diff_output" ]]; then
        return 0
    fi
    
    # Parse diff to get added lines with their line numbers
    local current_line=0
    local in_hunk=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^@@\ -[0-9]+,[0-9]+\ \+([0-9]+),[0-9]+\ @@ ]]; then
            # Extract starting line number for new file
            current_line=${BASH_REMATCH[1]}
            in_hunk=true
            continue
        fi

        if [[ "$in_hunk" == "true" ]]; then
            if [[ "$line" =~ ^[+] ]]; then
                # This is an added line
                local content="${line:1}"  # Remove the + prefix
                echo "${current_line}:${content}"
                ((current_line++))
            elif [[ "$line" =~ ^[^-] ]]; then
                # Context line or unchanged line
                ((current_line++))
            fi
            # Lines starting with - are deletions, don't increment line number
        fi
    done <<< "$diff_output"
}
export -f get_added_lines_with_numbers

get_added_lines_for_file() {
    local file="$1"
    local base_ref=$(get_base_ref)
    
    # Check if file exists (it might be deleted)
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    
    # Check if this is an untracked file
    if is_untracked_file "$file"; then
        # For untracked files, all lines are "added"
        while IFS= read -r line; do
            echo "+${line}"
        done < "$file"
        return 0
    fi
    
    if is_running_in_ci; then
        # In CI, get committed changes
        local committed_lines=$(git diff "${base_ref}...HEAD" -- "$file" | grep -E '^\+' | grep -v '^\+\+\+' || echo "")
        echo "$committed_lines"
    else
        # Locally, get current state vs base
        git diff "${base_ref}" -- "$file" | grep -E '^\+' | grep -v '^\+\+\+' || echo ""
    fi
}
export -f get_added_lines_for_file

# Check if rule should run for target branch
should_run_rule_for_target() {
    local rule_json=$1
    local current_target=$(get_target_branch)
    
    # Get target_branches from rule
    local target_branches=$(echo "$rule_json" | jq -r '.target_branches[]?' 2>/dev/null || echo "")
    
    # If no target_branches specified, rule runs for all branches
    if [[ -z "$target_branches" ]]; then
        return 0
    fi
    
    # Check if current target matches any of the specified branches
    while IFS= read -r target; do
        [[ -z "$target" ]] && continue
        
        # Handle wildcards
        if [[ "$target" == "*" ]]; then
            return 0
        fi
        
        # Exact match
        if [[ "$current_target" == "$target" ]]; then
            return 0
        fi
        
        # Pattern match (e.g., release/* matches release/1.2.3)
        if [[ "$current_target" == $target ]]; then
            return 0
        fi
    done <<< "$target_branches"
    
    return 1
}

# Check branch naming rules
check_branch_name() {
    local rule_json=$1
    
    local rule_id=$(echo "$rule_json" | jq -r '.id')
    local rule_name=$(echo "$rule_json" | jq -r '.name')
    local severity=$(echo "$rule_json" | jq -r '.severity')
    local message=$(echo "$rule_json" | jq -r '.message')
    
    # Support both old target_branch and new target_branches format
    local target_branches=$(echo "$rule_json" | jq -r '.target_branches[]?' 2>/dev/null || echo "")
    if [[ -z "$target_branches" ]]; then
        # Fallback to old format
        target_branches=$(echo "$rule_json" | jq -r '.target_branch // "*"')
    fi
    
    local allowed_patterns=$(echo "$rule_json" | jq -r '.allowed_patterns[]')
    
    log "INFO" "Checking branch name rule: $rule_name"
    
    local current_target=$(get_target_branch)
    local source_branch=$(get_source_branch)
    
    # Check if this rule applies to the current target branch
    local rule_applies=false
    while IFS= read -r target_pattern; do
        [[ -z "$target_pattern" ]] && continue
        
        if [[ "$target_pattern" == "*" ]]; then
            rule_applies=true
            break
        fi
        
        # Exact match
        if [[ "$current_target" == "$target_pattern" ]]; then
            rule_applies=true
            break
        fi
        
        # Pattern match (e.g., release/* matches release/1.2.3)
        if [[ "$current_target" == $target_pattern ]]; then
            rule_applies=true
            break
        fi
    done <<< "$target_branches"
    
    if [[ "$rule_applies" == "false" ]]; then
        log "INFO" "Rule does not apply to target branch: $current_target"
        return 0
    fi
    
    log "INFO" "Checking source branch: $source_branch against target: $current_target"
    
    # Check if source branch matches any allowed pattern
    local matches=false
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        
        # Exact match
        if [[ "$source_branch" == "$pattern" ]]; then
            matches=true
            break
        fi
        
        # Pattern match (e.g., feature/* matches feature/my-branch)
        if [[ "$source_branch" == $pattern ]]; then
            matches=true
            break
        fi
    done <<< "$allowed_patterns"
    
    if [[ "$matches" == "false" ]]; then
        log "MATCH" "Branch name violation: $source_branch does not match allowed patterns for target $current_target"
        local allowed_list=$(echo "$allowed_patterns" | tr '\n' ', ' | sed 's/,$//')
        local detail="Source branch '$source_branch' does not match allowed patterns for merging to '$current_target'. Allowed patterns: $allowed_list"
        add_result "$severity" "$rule_id" "$rule_name" "$message" "$detail" "BRANCH_NAME"
    fi
}

# Check dependent file modification rules
check_dependent_file() {
    local rule_json=$1
    local changed_files=$2
    
    local rule_id=$(echo "$rule_json" | jq -r '.id')
    local rule_name=$(echo "$rule_json" | jq -r '.name')
    local severity=$(echo "$rule_json" | jq -r '.severity')
    local message=$(echo "$rule_json" | jq -r '.message')
    local source_patterns=$(echo "$rule_json" | jq -r '.source_patterns[]')
    local dependent_files=$(echo "$rule_json" | jq -r '.dependent_files[]')
    local source_folders=$(echo "$rule_json" | jq -r '.source_folders[]?' 2>/dev/null || echo "")
    
    log "INFO" "Checking dependent file rule: $rule_name"
    
    local source_modified=false
    local dependent_modified=false
    local matched_files=()
    
    # Check if any source files were modified
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        # Check source patterns
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            
            local should_check_pattern=true
            
            # If source_folders is specified, file must be in one of those folders
            if [[ -n "$source_folders" ]]; then
                should_check_pattern=false
                while IFS= read -r folder; do
                    [[ -z "$folder" ]] && continue
                    if [[ "$file" == $folder* ]]; then
                        should_check_pattern=true
                        break
                    fi
                done <<< "$source_folders"
            fi
            
            if [[ "$should_check_pattern" == "true" ]] && [[ "$file" == $pattern ]]; then
                log "MATCH" "Source file modified: $file matches pattern $pattern"
                source_modified=true
                matched_files+=("$file")
            fi
        done <<< "$source_patterns"
    done <<< "$changed_files"
    
    # If source files were modified, check if dependent files were also modified
    if [[ "$source_modified" == "true" ]]; then
        while IFS= read -r dependent_pattern; do
            [[ -z "$dependent_pattern" ]] && continue
            
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                if [[ "$file" == $dependent_pattern ]]; then
                    log "INFO" "Dependent file found modified: $file"
                    dependent_modified=true
                    break 2
                fi
            done <<< "$changed_files"
        done <<< "$dependent_files"
        
        # If dependent files were not modified, report violation
        if [[ "$dependent_modified" == "false" ]]; then
            log "MATCH" "Source files modified but dependent files not updated"
            local matched_files_str=$(IFS=', '; echo "${matched_files[*]}")
            local dependent_files_str=$(echo "$dependent_files" | tr '\n' ', ' | sed 's/,$//')
            local detail="Modified source files: $matched_files_str. Expected dependent files to be updated: $dependent_files_str"
            add_result "$severity" "$rule_id" "$rule_name" "$message" "$detail" "$matched_files_str"
        fi
    fi
}

# Run custom checks from the custom directory
run_custom_checks() {
    if [[ ! -d "$CUSTOM_DIR" ]]; then
        log "INFO" "No custom checks directory found at $CUSTOM_DIR"
        return 0
    fi
    
    log "INFO" "Running custom checks from $CUSTOM_DIR"
    
    # Find all executable shell scripts in the custom directory
    local custom_scripts=$(find "$CUSTOM_DIR" -type f -name "*.sh" 2>/dev/null || echo "")
    
    if [[ -z "$custom_scripts" ]]; then
        log "INFO" "No custom check scripts found"
        return 0
    fi
    
    # Export necessary variables and functions for custom scripts
    export PROJECT_ROOT
    export BASE_BRANCH
    export RULES_FILE
    export OUTPUT_FILE
    
    # Run each custom script
    while IFS= read -r script; do
        log "INFO" "Running custom check: $(basename "$script")"
        
        # Source the script so it has access to our helper functions
        # This is safer than executing it directly
        if source "$script"; then
            log "INFO" "Custom check completed: $(basename "$script")"
        else
            log "ERROR" "Custom check failed: $(basename "$script")"
            add_result "error" "custom_check_failure" "Custom Check Failure" \
                "The custom check script $(basename "$script") failed to execute properly." \
                "Check the script for errors." "$(basename "$script")"
        fi
    done <<< "$custom_scripts"
    
    log "INFO" "All custom checks completed"
}

# Initialize results JSON
init_results() {
    cat > "$OUTPUT_FILE" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "branch": "$(git rev-parse --abbrev-ref HEAD)",
  "base_branch": "${BASE_BRANCH}",
  "target_branch": "$(get_target_branch)",
  "commit": "$(git rev-parse HEAD)",
  "results": {
    "errors": [],
    "warnings": [],
    "infos": []
  },
  "summary": {
    "error_count": 0,
    "warning_count": 0,
    "info_count": 0,
    "passed": false
  }
}
EOF
}

# Add result to results array
add_result() {
    local severity=$1
    local rule_id=$2
    local rule_name=$3
    local message=$4
    local details=$5
    local file=$6
    local line_number=${7:-0}

    # Escape JSON strings
    message=$(echo -n "$message" | jq -Rs . 2>&1)
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to escape message: $message"
        return 1
    fi

    details=$(echo -n "$details" | jq -Rs . 2>&1)
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to escape details: $details"
        return 1
    fi

    file=$(echo -n "$file" | jq -Rs . 2>&1)
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to escape file: $file"
        return 1
    fi

    rule_name=$(echo -n "$rule_name" | jq -Rs . 2>&1)
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to escape rule_name: $rule_name"
        return 1
    fi
    
    # Create result object
    local result=$(cat <<EOF
{
  "rule_id": "$rule_id",
  "rule_name": $rule_name,
  "severity": "$severity",
  "message": $message,
  "details": $details,
  "file": $file,
  "line": $line_number
}
EOF
)

    # Append result to results array
    results+=("$result")

    # Update counters
    case $severity in
        error) ((++errors)) ;;
        warning) ((++warnings)) ;;
        info) ((++info)) ;;
    esac

    log "DEBUG" "Result added successfully"
}
# Make add_result available to custom scripts
export -f add_result

# Update results in JSON file after processing all rules
update_results() {
    local temp_file=$(mktemp)

    # Create initial JSON structure with empty results arrays
    cat > "$temp_file" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "branch": "$(git rev-parse --abbrev-ref HEAD)",
  "base_branch": "${BASE_BRANCH}",
  "target_branch": "$(get_target_branch)",
  "commit": "$(git rev-parse HEAD)",
  "results": {
    "errors": [],
    "warnings": [],
    "infos": []
  },
  "summary": {
    "error_count": $errors,
    "warning_count": $warnings,
    "info_count": $info,
    "passed": false
  }
}
EOF

    # Append results to the appropriate arrays
    for result in "${results[@]}"; do
        local severity=$(echo "$result" | jq -r '.severity')
        local severity_key="${severity}s"
        
        jq ".results.${severity_key} += [$result]" "$temp_file" > "$OUTPUT_FILE"
        if [[ $? -ne 0 ]]; then
            log "ERROR" "Failed to update results in JSON file: $OUTPUT_FILE"
            return 1
        fi
        
        mv "$OUTPUT_FILE" "$temp_file"
    done

    # Update summary
    jq ".summary.error_count = $errors | 
        .summary.warning_count = $warnings | 
        .summary.info_count = $info | 
        .summary.passed = $(if [[ $errors -eq 0 ]]; then echo "true"; else echo "false"; fi)" "$temp_file" > "$OUTPUT_FILE"
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to update summary in JSON file: $OUTPUT_FILE"
        return 1
    fi

    mv "$temp_file" "$OUTPUT_FILE"
    log "DEBUG" "Results and summary updated successfully"
}

# Check diff size rules
check_diff_size() {
    local rule_json=$1
    
    local rule_id=$(echo "$rule_json" | jq -r '.id')
    local rule_name=$(echo "$rule_json" | jq -r '.name')
    local severity=$(echo "$rule_json" | jq -r '.severity')
    local message=$(echo "$rule_json" | jq -r '.message')
    local max_lines=$(echo "$rule_json" | jq -r '.max_lines // 500')
    local count_type=$(echo "$rule_json" | jq -r '.count_type // "added"')
    
    log "INFO" "Checking diff size rule: $rule_name (max: $max_lines lines, type: $count_type)"
    
    local base_ref=$(get_base_ref)
    
    # Find merge base for consistent comparison
    local merge_base=$(git merge-base "$base_ref" HEAD 2>/dev/null || echo "$base_ref")
    log "INFO" "Using merge base: $merge_base for comparison with $base_ref"
    
    # Get diff stats using consistent approach
    local diff_stats=0
    local comparison_target=""
    
    if is_running_in_ci; then
        # In CI, compare merge-base to HEAD (committed changes only)
        comparison_target="HEAD"
    else
        # Locally, compare merge-base to working tree (includes uncommitted changes)
        comparison_target=""  # Empty means working tree
    fi
    
    case "$count_type" in
        "added")
            diff_stats=$(git diff --numstat "$merge_base" $comparison_target | awk '{added += $1} END {print added+0}')
            
            # Add untracked files only in local mode
            if ! is_running_in_ci; then
                local untracked_lines=0
                local untracked_files=$(get_untracked_files)
                if [[ -n "$untracked_files" ]]; then
                    while IFS= read -r file; do
                        [[ -z "$file" ]] && continue
                        [[ -f "$file" ]] && untracked_lines=$((untracked_lines + $(wc -l < "$file" 2>/dev/null || echo 0)))
                    done <<< "$untracked_files"
                fi
                diff_stats=$((diff_stats + untracked_lines))
            fi
            ;;
        "removed")
            diff_stats=$(git diff --numstat "$merge_base" $comparison_target | awk '{removed += $2} END {print removed+0}')
            ;;
        "total"|*)
            diff_stats=$(git diff --numstat "$merge_base" $comparison_target | awk '{added += $1; removed += $2} END {print added+removed+0}')
            
            # Add untracked files only in local mode
            if ! is_running_in_ci; then
                local untracked_lines=0
                local untracked_files=$(get_untracked_files)
                if [[ -n "$untracked_files" ]]; then
                    while IFS= read -r file; do
                        [[ -z "$file" ]] && continue
                        [[ -f "$file" ]] && untracked_lines=$((untracked_lines + $(wc -l < "$file" 2>/dev/null || echo 0)))
                    done <<< "$untracked_files"
                fi
                diff_stats=$((diff_stats + untracked_lines))
            fi
            ;;
    esac
    
    local line_count=${diff_stats:-0}
    
    log "INFO" "Diff stats: $line_count lines ($count_type) from merge-base $merge_base"
    
    if (( line_count > max_lines )); then
        log "MATCH" "Diff size exceeds limit: $line_count > $max_lines"
        local detail="This PR/diff has $line_count $count_type lines (limit: $max_lines). Consider breaking it into smaller changes."
        add_result "$severity" "$rule_id" "$rule_name" "$message" "$detail" "DIFF_SIZE"
        
        # Add file breakdown for context
        local file_breakdown=$(git diff --numstat "$merge_base" $comparison_target | sort -nr | head -10)
        
        if [[ -n "$file_breakdown" ]]; then
            local breakdown_detail="Top files by line changes:\n$file_breakdown"
            add_result "info" "${rule_id}_breakdown" "Large Diff - File Breakdown" "Files contributing most to the large diff" "$breakdown_detail" "DIFF_BREAKDOWN"
        fi
    fi
}

# Check file pattern rules
check_file_pattern() {
    local rule_json=$1
    local changed_files=$2
    
    local rule_id=$(echo "$rule_json" | jq -r '.id')
    local rule_name=$(echo "$rule_json" | jq -r '.name')
    local severity=$(echo "$rule_json" | jq -r '.severity')
    local message=$(echo "$rule_json" | jq -r '.message')
    local patterns=$(echo "$rule_json" | jq -r '.patterns[]')
    
    log "INFO" "Checking rule: $rule_name"
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            
            # Convert glob pattern to find pattern
            if [[ "$file" == $pattern ]]; then
                log "MATCH" "File $file matches pattern $pattern"
                add_result "$severity" "$rule_id" "$rule_name" "$message" "File matched: $file" "$file"
            fi
        done <<< "$patterns"
    done <<< "$changed_files"
}

# Check code pattern rules (only in added lines)
check_code_pattern() {
    local rule_json=$1
    local changed_files=$2
    
    local rule_id=$(echo "$rule_json" | jq -r '.id')
    local rule_name=$(echo "$rule_json" | jq -r '.name')
    local severity=$(echo "$rule_json" | jq -r '.severity')
    local message=$(echo "$rule_json" | jq -r '.message')
    local patterns=$(echo "$rule_json" | jq -r '.patterns[]')
    local file_patterns=$(echo "$rule_json" | jq -r '.file_patterns[]?' 2>/dev/null || echo "")
    local exclude_patterns=$(echo "$rule_json" | jq -r '.exclude_patterns[]?' 2>/dev/null || echo "")
   
    log "INFO" "Checking code pattern rule: $rule_name"
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Skip if file doesn't exist (deleted files)
        [[ ! -f "$file" ]] && continue

        # Check if file matches file_patterns
        local should_check=false
        
        if [[ -z "$file_patterns" ]] || [[ "$file_patterns" == "**" ]]; then
            should_check=true
        else
            while IFS= read -r file_pattern; do
                if [[ -n "$file_pattern" ]] && [[ "$file" == $file_pattern ]]; then
                    should_check=true
                    break
                fi
            done <<< "$file_patterns"
        fi
        
        if [[ "$should_check" == "false" ]]; then
            continue
        fi
        
        # Get added lines with line numbers using our helper function
        local added_lines=$(get_added_lines_with_numbers "$file")
           
        
        if [[ -z "$added_lines" ]]; then
            continue
        fi
        
        # Check each added line
        while IFS= read -r line_info; do
            [[ -z "$line_info" ]] && continue
            
            local line_number="${line_info%%:*}"
            local content="${line_info#*:}"
            
            # Check exclude patterns first
            local excluded=false
            if [[ -n "$exclude_patterns" ]]; then
                while IFS= read -r exclude_pattern; do
                    [[ -z "$exclude_pattern" ]] && continue
                    if [[ "$content" == *"$exclude_pattern"* ]]; then
                        excluded=true
                        break
                    fi
                done <<< "$exclude_patterns"
            fi
            
            if [[ "$excluded" == "false" ]]; then
                # Check each pattern against the content
                while IFS= read -r pattern; do
                    [[ -z "$pattern" ]] && continue
                    # Use grep for regex matching
                    if echo "$content" | grep -qE "$pattern" 2>/dev/null; then
                        log "MATCH" "Pattern '$pattern' found in $file at line $line_number"
                        local detail="Pattern found in added line: $(echo "$content" | head -c 100)..."
                        add_result "$severity" "$rule_id" "$rule_name" "$message" "$detail" "$file" "$line_number"
                    fi
                done <<< "$patterns"
            fi
        done <<< "$added_lines"
    done <<<"$changed_files"
}

# Check file size rules
check_file_size() {
    local rule_json=$1
    local changed_files=$2
    
    local rule_id=$(echo "$rule_json" | jq -r '.id')
    local rule_name=$(echo "$rule_json" | jq -r '.name')
    local severity=$(echo "$rule_json" | jq -r '.severity')
    local message=$(echo "$rule_json" | jq -r '.message')
    local max_size_kb=$(echo "$rule_json" | jq -r '.max_size_kb')
    local file_patterns=$(echo "$rule_json" | jq -r '.file_patterns[]?' 2>/dev/null || echo "**")
    local exclude_patterns=$(echo "$rule_json" | jq -r '.exclude_patterns[]?' 2>/dev/null || echo "")
    
    log "INFO" "Checking file size rule: $rule_name"
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue  # Skip deleted files
        
        # Check exclude patterns
        local excluded=false
        if [[ -n "$exclude_patterns" ]]; then
            while IFS= read -r exclude_pattern; do
                [[ -z "$exclude_pattern" ]] && continue
                if [[ "$file" == $exclude_pattern ]]; then
                    excluded=true
                    break
                fi
            done <<< "$exclude_patterns"
        fi
        
        [[ "$excluded" == "true" ]] && continue
        
        # Check file size
        local size_kb=$(( $(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0) / 1024 ))
        
        if (( size_kb > max_size_kb )); then
            log "MATCH" "File $file exceeds size limit: ${size_kb}KB > ${max_size_kb}KB"
            local detail="File size: ${size_kb}KB (limit: ${max_size_kb}KB)"
            add_result "$severity" "$rule_id" "$rule_name" "$message" "$detail" "$file"
        fi
    done <<< "$changed_files"
}

# Check if file should be excluded
is_excluded_file() {
    local file=$1
    local exclude_patterns=$(jq -r '.settings.exclude_files[]?' "$RULES_FILE" 2>/dev/null)
    
    if [[ -n "$exclude_patterns" ]]; then
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            if [[ "$file" == $pattern ]]; then
                return 0  # File is excluded
            fi
        done <<< "$exclude_patterns"
    fi
    
    return 1  # File is not excluded
}

# Process all rules
process_rules() {
    local changed_files=$(get_changed_files)
    
    if [[ -z "$changed_files" ]]; then
        log "WARN" "No changed files found"
        return 0
    fi
    
    # Filter out excluded files
    local filtered_files=""
    while IFS= read -r file; do
        if ! is_excluded_file "$file"; then
            filtered_files+="${file}"$'\n'
        else
            log "INFO" "Excluding file: $file"
        fi
    done <<< "$changed_files"

    # Process rules from core-rules.json
    local core_rules_file="${SCRIPT_ROOT}/core-rules.json"
    if [[ -f "$core_rules_file" ]]; then
        log "INFO" "Processing rules from core-rules.json"
        local core_rules=$(jq -c '.rules[]' "$core_rules_file" 2>/dev/null)
        while IFS= read -r rule; do
            [[ -z "$rule" ]] && continue
            process_single_rule "$rule" "$filtered_files"
        done <<< "$core_rules"
    else
        log "WARN" "Core Rules file not found at $RULES_FILE"
    fi

    if [[ -f "$RULES_FILE" ]]; then
        log "INFO" "Processing rules from rules.json"
        local rules=$(jq -c '.rules[]' "$RULES_FILE" 2>/dev/null)
        while IFS= read -r rule; do
            [[ -z "$rule" ]] && continue
            process_single_rule "$rule" "$filtered_files"
        done <<< "$rules"
    else
        log "WARN" "Rules file not found at $RULES_FILE"
    fi
}

process_single_rule() {
    local rule_json=$1
    local changed_files=$2

    # Check if rule should run for current target branch
    if ! should_run_rule_for_target "$rule_json"; then
        local rule_name=$(echo "$rule_json" | jq -r '.name')
        log "INFO" "Skipping rule '$rule_name' - not applicable for target branch $(get_target_branch)"
        return 0
    fi

    local rule_type=$(echo "$rule_json" | jq -r '.type')

    case "$rule_type" in
        file_pattern)
            check_file_pattern "$rule_json" "$changed_files"
            ;;
        code_pattern)
            check_code_pattern "$rule_json" "$changed_files"
            ;;
        file_size)
            check_file_size "$rule_json" "$changed_files"
            ;;
        diff_size|pr_size)
            check_diff_size "$rule_json"
            ;;
        dependent_file)
            check_dependent_file "$rule_json" "$changed_files"
            ;;
        branch_naming)
            check_branch_name "$rule_json"
            ;;
        *)
            log "WARN" "Unknown rule type: $rule_type"
            ;;
    esac
}

# Update summary in results
update_summary() {
    local passed="true"
    local fail_on_errors=$(jq -r '.settings.fail_on_errors' "$RULES_FILE" 2>/dev/null || echo "true")
    local max_warnings=$(jq -r '.settings.max_warnings' "$RULES_FILE" 2>/dev/null || echo "999")
    
    # Check if should fail
    if [[ "$fail_on_errors" == "true" ]] && (( errors > 0 )); then
        passed="false"
    fi
    
    if (( warnings > max_warnings )); then
        passed="false"
    fi
    
    # Update summary
    local temp_file=$(mktemp)
    jq ".summary.error_count = $errors | 
        .summary.warning_count = $warnings | 
        .summary.info_count = $info | 
        .summary.passed = $passed" "$OUTPUT_FILE" > "$temp_file"
    mv "$temp_file" "$OUTPUT_FILE"
}

# Print summary to stdout
print_summary() {
    echo ""
    echo "========================================="
    echo "         CodeGuardian Analysis Summary         "
    echo "========================================="
    
    local target_branch=$(get_target_branch)
    local source_branch=$(get_source_branch)
    
    echo -e "${BLUE}Source Branch: ${source_branch}${NC}"
    echo -e "${BLUE}Target Branch: ${target_branch}${NC}"
    echo ""
    
    if (( errors == 0 && warnings == 0 && info == 0 )); then
        echo -e "${GREEN}✅ All checks passed!${NC}"
    else
        if (( errors > 0 )); then
            echo -e "${RED}❌ Errors: $errors${NC}"
        fi
        if (( warnings > 0 )); then
            echo -e "${YELLOW}⚠️  Warnings: $warnings${NC}"
        fi
        if (( info > 0 )); then
            echo -e "${BLUE}ℹ️  Info: $info${NC}"
        fi
    fi
    
    echo -e "${BLUE}📝 Analysis included uncommitted changes${NC}"
    local untracked_count=$(get_untracked_files | wc -l | tr -d ' ')
    if [[ "$untracked_count" -gt 0 ]]; then
        echo -e "${BLUE}📄 Analyzed $untracked_count untracked files${NC}"
    fi
    
    echo "========================================="
    echo ""
    echo "Full results saved to: $OUTPUT_FILE"
    
    return 0
}

# Main execution
main() {
    echo "🔍 Starting CodeGuardian Analysis..."
    
    # Change to project root for git operations
    cd "$REPO_ROOT"

    # Check dependencies
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        echo "Error: git is required but not installed."
        exit 1
    fi
    
    # Check if rules file exists
    if [[ ! -f "$RULES_FILE" ]]; then
        echo "Error: Rules file not found at $RULES_FILE"
        exit 1
    fi
    
    # Initialize results
    init_results
    
    # Process rules
    process_rules

    # Run custom checks
    run_custom_checks
    
    # Save results to JSON file
    update_results

    # Update summary
    update_summary
    
    # Print summary and exit with appropriate code
    print_summary
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--rules)
            RULES_FILE="$2"
            shift 2
            ;;
        -c|--custom-dir)
            CUSTOM_DIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -b|--base)
            BASE_BRANCH="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -r, --rules FILE         Path to rules.json file (default: ./CodeGuardian/rules.json)"
            echo "  -c, --custom-dir DIR     Path to custom checks directory (default: ./CodeGuardian/custom-checks)"
            echo "  -o, --output FILE        Output file for results (default: ./codeguardian-results.json)"
            echo "  -b, --base BRANCH        Base branch to compare against (default: main)"
            echo "  -t, --target BRANCH      Target branch we're merging to"
            echo "  -v, --verbose            Enable verbose logging"
            echo "  -u, --include-uncommitted Include uncommitted changes in analysis"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main
