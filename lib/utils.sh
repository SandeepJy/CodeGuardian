#!/bin/bash
#
# utils.sh - Utility functions for the danger system
#

# Log function
log() {
    local level=$1
    shift
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $level: $*" >&2
    fi
}

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi
    return 0
}

# Get the number of commits ahead of base branch
get_commits_ahead() {
    local base_branch=${1:-main}
    git rev-list --count "${base_branch}..HEAD" 2>/dev/null || echo "0"
}

# Check if base branch exists
check_base_branch() {
    local base_branch=${1:-main}
    if ! git rev-parse --verify "$base_branch" > /dev/null 2>&1; then
        echo "Error: Base branch '$base_branch' does not exist"
        echo "Try fetching from remote: git fetch origin $base_branch"
        return 1
    fi
    return 0
}

# Format file size in human readable format
format_file_size() {
    local size_bytes=$1
    local size_kb=$((size_bytes / 1024))
    local size_mb=$((size_kb / 1024))
    
    if (( size_mb > 0 )); then
        echo "${size_mb}MB"
    elif (( size_kb > 0 )); then
        echo "${size_kb}KB"
    else
        echo "${size_bytes}B"
    fi
}

# Check if running in CI environment
is_ci() {
    [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${JENKINS_URL:-}" ]]
}

# Get current branch name
get_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

# Get current commit hash
get_current_commit() {
    git rev-parse HEAD
}

# Check for uncommitted changes
has_uncommitted_changes() {
    ! git diff-index --quiet HEAD --
}