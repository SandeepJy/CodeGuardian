# CodeGuardian

A comprehensive code analysis system that automatically checks pull requests and commits against configurable rules. CodeGuardian helps maintain code quality, enforce coding standards, and prevent common issues before they reach the main branch.

## Features

- **Automated Code Analysis**: Analyzes git diffs against configurable rules
- **Multiple Rule Types**: Support for file patterns, code patterns, file sizes, diff sizes, branch naming, and dependent file checks
- **Custom Rules**: Extensible system for custom checks and validations
- **CI/CD Integration**: Works seamlessly with GitHub Actions and other CI systems
- **Local Testing**: Test rules locally before pushing changes
- **Flexible Configuration**: JSON-based rule configuration with pattern matching
- **Branch-Specific Rules**: Different rules for different target branches

## Quick Start

### 1. Setup in Your Repository

1. **Create CodeGuardian directory structure**:

   ```bash
   mkdir CodeGuardian
   ```

2. **Add the main script** to your repository root:

   ```bash
   # Download the main runner script
   curl -o run-codeguardian.sh https://raw.githubusercontent.com/SandeepJy/CodeGuardian/main/scripts/run-codeguardian.sh
   chmod +x run-codeguardian.sh
   ```

3. **Create your rules configuration**:

   ```bash
   # Create rules.json in the CodeGuardian directory
   cat > CodeGuardian/rules.json << 'EOF'
   {
     "rules": [
       {
         "id": "large-pr",
         "name": "Large Pull Request",
         "description": "Large PRs are harder to review",
         "severity": "warning",
         "type": "diff_size",
         "max_lines": 500,
         "count_type": "total",
         "message": "This PR is quite large. Consider breaking it into smaller ones."
       }
     ],
     "settings": {
       "fail_on_errors": true,
       "max_warnings": 10,
       "exclude_files": [
         "**/*.lock",
         "**/package-lock.json"
       ]
     }
   }
   EOF
   ```

4. **Configure .gitignore** (see [Gitignore Configuration](#gitignore-configuration) section)

### 2. Test Locally

```bash
# Test your rules against current changes
./run-codeguardian.sh main
```

### 3. Integrate with CI/CD

Add to your GitHub Actions workflow:

```yaml
name: CodeGuardian Analysis
on: [pull_request]

jobs:
  codeguardian:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Run CodeGuardian
        run: ./run-codeguardian.sh ${{ github.base_ref }}
```

## Rule Types

CodeGuardian supports several types of rules to analyze different aspects of your code changes. Each rule type has specific required and optional parameters.

### 1. File Pattern Rules (`file_pattern`)

Check for files matching specific patterns.

**Required Parameters:**

- `patterns` (array): Glob patterns to match against file paths

**Optional Parameters:**

- `target_branches` (array): Target branches where this rule applies (default: all branches)

**Example:**

```json
{
  "id": "no-temp-files",
  "name": "No Temporary Files",
  "description": "Prevent temporary files from being committed",
  "severity": "error",
  "type": "file_pattern",
  "patterns": [
    "**/*.tmp",
    "**/*.temp",
    "**/temp/**",
    "**/.DS_Store",
    "**/Thumbs.db"
  ],
  "message": "Temporary files should not be committed to the repository"
}
```

**Pattern Examples:**

- `**/*.tmp` - Any .tmp file anywhere
- `**/temp/**` - Any file in a temp directory
- `src/**/*.backup` - Backup files in src directory
- `**/node_modules/**` - Files in node_modules

### 2. Code Pattern Rules (`code_pattern`)

Check for specific code patterns in added lines only.

**Required Parameters:**

- `patterns` (array): Regex patterns to search for in code

**Optional Parameters:**

- `file_patterns` (array): File patterns to limit search scope (default: all files)
- `exclude_patterns` (array): Code patterns to exclude from matching
- `target_branches` (array): Target branches where this rule applies

**Example:**

```json
{
  "id": "no-console-logs",
  "name": "No Console Logs",
  "description": "Prevent console.log statements in production code",
  "severity": "warning",
  "type": "code_pattern",
  "patterns": [
    "console\\.log\\(",
    "console\\.warn\\(",
    "console\\.error\\(",
    "console\\.debug\\("
  ],
  "file_patterns": ["**/*.js", "**/*.ts", "**/*.jsx", "**/*.tsx"],
  "exclude_patterns": [
    "console\\.log\\(.*test.*\\)",
    "console\\.log\\(.*debug.*\\)"
  ],
  "message": "Console statements should be removed before production"
}
```

**Pattern Examples:**

- `console\\.log` - Matches console.log (escaped dot)
- `TODO|FIXME|HACK` - Matches TODO, FIXME, or HACK comments
- `password\\s*=\\s*[\"'][^\"']*[\"']` - Matches password assignments
- `eval\\s*\\(` - Matches eval() function calls

### 3. File Size Rules (`file_size`)

Check for files exceeding size limits.

**Required Parameters:**

- `max_size_kb` (number): Maximum file size in kilobytes

**Optional Parameters:**

- `file_patterns` (array): File patterns to check (default: all files)
- `exclude_patterns` (array): File patterns to exclude from size checks
- `target_branches` (array): Target branches where this rule applies

**Example:**

```json
{
  "id": "large-file-check",
  "name": "Large File Check",
  "description": "Prevent large files from being committed",
  "severity": "warning",
  "type": "file_size",
  "max_size_kb": 1024,
  "file_patterns": ["**/*.js", "**/*.ts", "**/*.py", "**/*.java"],
  "exclude_patterns": [
    "**/*.min.js",
    "**/*.bundle.js",
    "**/vendor/**",
    "**/node_modules/**"
  ],
  "message": "Large file detected. Consider if this file is necessary or if it can be optimized."
}
```

**Size Examples:**

- `max_size_kb: 100` - 100KB limit
- `max_size_kb: 1024` - 1MB limit
- `max_size_kb: 5120` - 5MB limit

### 4. Diff Size Rules (`diff_size`)

Check for pull requests that are too large.

**Required Parameters:**

- `max_lines` (number): Maximum number of lines allowed

**Optional Parameters:**

- `count_type` (string): What to count - `added`, `removed`, or `total` (default: `added`)
- `target_branches` (array): Target branches where this rule applies

**Example:**

```json
{
  "id": "large-pr",
  "name": "Large Pull Request",
  "description": "Large PRs are harder to review",
  "severity": "warning",
  "type": "diff_size",
  "max_lines": 500,
  "count_type": "total",
  "message": "This PR is quite large. Consider breaking it into smaller ones."
}
```

**Count Type Options:**

- `added`: Only count added lines (recommended for most cases)
- `removed`: Only count removed lines
- `total`: Count both added and removed lines

**Line Limit Examples:**

- `max_lines: 200` - Small PRs only
- `max_lines: 500` - Medium PRs
- `max_lines: 1000` - Large PRs allowed

### 5. Branch Naming Rules (`branch_naming`)

Enforce branch naming conventions.

**Required Parameters:**

- `allowed_patterns` (array): Patterns that branch names must match

**Optional Parameters:**

- `target_branches` (array): Target branches where this rule applies (default: all branches)

**Example:**

```json
{
  "id": "branch-naming",
  "name": "Branch Naming Convention",
  "description": "Enforce branch naming conventions",
  "severity": "error",
  "type": "branch_naming",
  "target_branches": ["main", "develop"],
  "allowed_patterns": [
    "feature/*",
    "bugfix/*",
    "hotfix/*",
    "release/*",
    "chore/*"
  ],
  "message": "Branch name must follow the naming convention"
}
```

**Pattern Examples:**

- `feature/*` - Matches feature/user-login, feature/payment-system
- `bugfix/*` - Matches bugfix/login-error, bugfix/memory-leak
- `hotfix/*` - Matches hotfix/security-patch, hotfix/critical-bug
- `release/*` - Matches release/v1.2.0, release/2023.1
- `chore/*` - Matches chore/update-deps, chore/cleanup

### 6. Dependent File Rules (`dependent_file`)

Ensure related files are updated together when source files change.

**Required Parameters:**

- `source_patterns` (array): Patterns for files that trigger the check
- `dependent_files` (array): Files that must be updated when source files change

**Optional Parameters:**

- `source_folders` (array): Folders to limit source pattern matching
- `target_branches` (array): Target branches where this rule applies

**Example:**

```json
{
  "id": "api-docs-update",
  "name": "API Documentation Update",
  "description": "API changes should include documentation updates",
  "severity": "warning",
  "type": "dependent_file",
  "source_patterns": [
    "**/api/**/*.js",
    "**/controllers/**/*.js",
    "**/routes/**/*.js"
  ],
  "source_folders": ["src/api", "src/controllers", "src/routes"],
  "dependent_files": ["docs/api.md", "README.md", "docs/endpoints.md"],
  "message": "API changes should include documentation updates"
}
```

**Use Cases:**

- API changes → Documentation updates
- Database schema changes → Migration files
- Configuration changes → Documentation updates
- Test file changes → Corresponding implementation files

## Rule Configuration

### Rule Properties

Each rule must have these required properties:

- `id`: Unique identifier for the rule
- `name`: Human-readable name
- `description`: Brief description of what the rule checks
- `severity`: `error`, `warning`, or `info`
- `type`: One of the supported rule types
- `message`: Message to display when rule is violated

### Severity Levels

- **error**: Fails the check and prevents merging
- **warning**: Shows warning but allows merging (unless `max_warnings` exceeded)
- **info**: Informational message only

### Global Settings

```json
{
  "settings": {
    "fail_on_errors": true,
    "max_warnings": 10,
    "exclude_files": ["**/*.lock", "**/package-lock.json", "**/yarn.lock"]
  }
}
```

- `fail_on_errors`: Whether to fail the check when errors are found
- `max_warnings`: Maximum number of warnings allowed before failing
- `exclude_files`: Glob patterns for files to exclude from analysis

## Parameter Reference

### Common Parameters

All rule types support these common parameters:

#### Required Parameters (All Rules)

- `id` (string): Unique identifier for the rule
- `name` (string): Human-readable name for the rule
- `description` (string): Brief description of what the rule checks
- `severity` (string): `error`, `warning`, or `info`
- `type` (string): One of: `file_pattern`, `code_pattern`, `file_size`, `diff_size`, `branch_naming`, `dependent_file`
- `message` (string): Message to display when rule is violated

#### Optional Parameters (All Rules)

- `target_branches` (array): Target branches where this rule applies (default: all branches)

### Rule-Specific Parameters

#### File Pattern Rules (`file_pattern`)

- `patterns` (array, **required**): Glob patterns to match against file paths

#### Code Pattern Rules (`code_pattern`)

- `patterns` (array, **required**): Regex patterns to search for in code
- `file_patterns` (array, optional): File patterns to limit search scope (default: all files)
- `exclude_patterns` (array, optional): Code patterns to exclude from matching

#### File Size Rules (`file_size`)

- `max_size_kb` (number, **required**): Maximum file size in kilobytes
- `file_patterns` (array, optional): File patterns to check (default: all files)
- `exclude_patterns` (array, optional): File patterns to exclude from size checks

#### Diff Size Rules (`diff_size`)

- `max_lines` (number, **required**): Maximum number of lines allowed
- `count_type` (string, optional): What to count - `added`, `removed`, or `total` (default: `added`)

#### Branch Naming Rules (`branch_naming`)

- `allowed_patterns` (array, **required**): Patterns that branch names must match

#### Dependent File Rules (`dependent_file`)

- `source_patterns` (array, **required**): Patterns for files that trigger the check
- `dependent_files` (array, **required**): Files that must be updated when source files change
- `source_folders` (array, optional): Folders to limit source pattern matching

### Pattern Matching

#### Glob Patterns

Used in `file_patterns`, `exclude_patterns`, and `patterns` for file matching:

- `**/*.js` - All .js files anywhere
- `src/**/*.ts` - All .ts files in src directory and subdirectories
- `**/test/**` - All files in any test directory
- `*.tmp` - All .tmp files in root directory only
- `**/node_modules/**` - All files in node_modules directories

#### Regex Patterns

Used in `patterns` for code pattern matching:

- `console\\.log` - Matches console.log (dot must be escaped)
- `TODO|FIXME|HACK` - Matches any of these words
- `password\\s*=\\s*[\"'][^\"']*[\"']` - Matches password assignments
- `eval\\s*\\(` - Matches eval() function calls
- `\\b(debugger|alert)\\b` - Matches debugger or alert keywords

#### Branch Patterns

Used in `allowed_patterns` for branch naming:

- `feature/*` - Matches feature/user-login, feature/payment-system
- `bugfix/*` - Matches bugfix/login-error, bugfix/memory-leak
- `hotfix/*` - Matches hotfix/security-patch, hotfix/critical-bug
- `release/*` - Matches release/v1.2.0, release/2023.1
- `chore/*` - Matches chore/update-deps, chore/cleanup

### Data Types

- **string**: Text value
- **number**: Numeric value (integers and decimals)
- **array**: List of values `["value1", "value2"]`
- **boolean**: `true` or `false`

### Examples by Use Case

#### Prevent Temporary Files

```json
{
  "id": "no-temp-files",
  "name": "No Temporary Files",
  "description": "Prevent temporary files from being committed",
  "severity": "error",
  "type": "file_pattern",
  "patterns": ["**/*.tmp", "**/*.temp", "**/.DS_Store"],
  "message": "Temporary files should not be committed"
}
```

#### Enforce Code Standards

```json
{
  "id": "no-hardcoded-secrets",
  "name": "No Hardcoded Secrets",
  "description": "Prevent hardcoded secrets in code",
  "severity": "error",
  "type": "code_pattern",
  "patterns": [
    "password\\s*=\\s*[\"'][^\"']*[\"']",
    "api_key\\s*=\\s*[\"'][^\"']*[\"']",
    "secret\\s*=\\s*[\"'][^\"']*[\"']"
  ],
  "file_patterns": ["**/*.js", "**/*.py", "**/*.java"],
  "exclude_patterns": ["**/*.test.js", "**/*.spec.js"],
  "message": "Hardcoded secrets should not be committed"
}
```

#### Limit File Sizes

```json
{
  "id": "max-file-size",
  "name": "Maximum File Size",
  "description": "Prevent large files from being committed",
  "severity": "warning",
  "type": "file_size",
  "max_size_kb": 500,
  "file_patterns": ["**/*.js", "**/*.css"],
  "exclude_patterns": ["**/*.min.js", "**/*.bundle.js"],
  "message": "File exceeds size limit"
}
```

#### Control PR Size

```json
{
  "id": "pr-size-limit",
  "name": "Pull Request Size Limit",
  "description": "Prevent overly large pull requests",
  "severity": "warning",
  "type": "diff_size",
  "max_lines": 300,
  "count_type": "added",
  "target_branches": ["main"],
  "message": "Pull request is too large for main branch"
}
```

#### Enforce Branch Naming

```json
{
  "id": "branch-convention",
  "name": "Branch Naming Convention",
  "description": "Enforce consistent branch naming",
  "severity": "error",
  "type": "branch_naming",
  "target_branches": ["main", "develop"],
  "allowed_patterns": ["feature/*", "bugfix/*", "hotfix/*"],
  "message": "Branch name must follow convention"
}
```

#### Ensure Documentation Updates

```json
{
  "id": "docs-update",
  "name": "Documentation Update Required",
  "description": "Ensure documentation is updated with API changes",
  "severity": "warning",
  "type": "dependent_file",
  "source_patterns": ["**/api/**/*.js", "**/controllers/**/*.js"],
  "source_folders": ["src/api", "src/controllers"],
  "dependent_files": ["docs/api.md", "README.md"],
  "message": "API changes require documentation updates"
}
```

## Custom Rules

### Creating Custom Check Scripts

You can create custom validation scripts in the `CodeGuardian/custom-checks/` directory:

```bash
mkdir CodeGuardian/custom-checks
```

Example custom check script (`CodeGuardian/custom-checks/license-check.sh`):

```bash
#!/bin/bash
# Custom check to ensure license headers are present

# Get all changed files
changed_files=$(get_changed_files)

# Check each file for license header
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    [[ ! -f "$file" ]] && continue

    # Skip non-source files
    if [[ ! "$file" =~ \.(js|ts|py|java|cpp|c|h)$ ]]; then
        continue
    fi

    # Check if file has license header
    if ! head -5 "$file" | grep -q "Copyright"; then
        add_result "warning" "missing_license" "Missing License Header" \
            "All source files should include a license header" \
            "File: $file" "$file"
    fi
done <<< "$changed_files"
```

### Available Helper Functions

Custom scripts have access to these helper functions:

- `get_changed_files()`: Get all changed files
- `get_added_files()`: Get all added files
- `get_modified_files()`: Get all modified files
- `get_added_lines_with_numbers(file)`: Get added lines with line numbers
- `add_result(severity, rule_id, rule_name, message, details, file, line)`: Add a result
- `log(level, message)`: Log a message
- `is_running_in_ci()`: Check if running in CI environment

## Gitignore Configuration

When using CodeGuardian in your repository, configure your `.gitignore` to:

**Include in repository:**

- `CodeGuardian/rules.json` - Your custom rules
- `CodeGuardian/custom-checks/` - Your custom check scripts
- `run-codeguardian.sh` - The main runner script

**Exclude from repository:**

- `CodeGuardian/CodeGuardian-*/` - Downloaded core scripts (downloaded on-demand)
- `CodeGuardian/codeguardian-results.json` - Analysis results (generated)

Example `.gitignore` additions:

```gitignore
# CodeGuardian - Include rules and custom checks, exclude downloaded core
CodeGuardian/CodeGuardian-*/
CodeGuardian/codeguardian-results.json

# Keep these in the repository:
# CodeGuardian/rules.json
# CodeGuardian/custom-checks/
# run-codeguardian.sh
```

## Usage Examples

### Basic Usage

```bash
# Run analysis against main branch
./run-codeguardian.sh main

# Run analysis against develop branch
./run-codeguardian.sh develop

# Force update of core scripts
UPDATE_CODEGUARDIAN=true ./run-codeguardian.sh main
```

### Advanced Configuration

```bash
# Use custom rules file
CODEGUARDIAN_DIR="./my-rules" ./run-codeguardian.sh main

# Use specific version of CodeGuardian
CODEGUARDIAN_VERSION="v1.2.0" ./run-codeguardian.sh main
```

### Environment Variables

- `CODEGUARDIAN_VERSION`: Version/tag to use (default: `main`)
- `CODEGUARDIAN_DIR`: Directory containing rules (default: `CodeGuardian`)
- `LOCAL_MODE`: Whether to run in local mode (default: `true`)
- `UPDATE_CODEGUARDIAN`: Force update of core scripts (default: `false`)

## CI/CD Integration

### GitHub Actions

```yaml
name: CodeGuardian Analysis
on:
  pull_request:
    branches: [main, develop]

jobs:
  codeguardian:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Run CodeGuardian Analysis
        run: |
          chmod +x run-codeguardian.sh
          ./run-codeguardian.sh ${{ github.base_ref }}

      - name: Comment PR with results
        if: always()
        uses: actions/github-script@v6
        with:
          script: |
            const fs = require('fs');
            if (fs.existsSync('CodeGuardian/codeguardian-results.json')) {
              const results = JSON.parse(fs.readFileSync('CodeGuardian/codeguardian-results.json', 'utf8'));
              const summary = results.summary;
              
              let comment = `## CodeGuardian Analysis Results\n\n`;
              comment += `- ✅ Errors: ${summary.error_count}\n`;
              comment += `- ⚠️ Warnings: ${summary.warning_count}\n`;
              comment += `- ℹ️ Info: ${summary.info_count}\n\n`;
              
              if (summary.passed) {
                comment += `🎉 **All checks passed!**`;
              } else {
                comment += `❌ **Checks failed!** Please review the issues above.`;
              }
              
              github.rest.issues.createComment({
                issue_number: context.issue.number,
                owner: context.repo.owner,
                repo: context.repo.repo,
                body: comment
              });
            }
```

### GitLab CI

```yaml
codeguardian:
  stage: test
  script:
    - chmod +x run-codeguardian.sh
    - ./run-codeguardian.sh $CI_MERGE_REQUEST_TARGET_BRANCH_NAME
  artifacts:
    reports:
      junit: CodeGuardian/codeguardian-results.json
```

## Troubleshooting

### Common Issues

1. **"CodeGuardian directory not found"**

   - Ensure you've created the `CodeGuardian` directory
   - Check that `rules.json` exists in the directory

2. **"jq is not installed"**

   - Install jq: `brew install jq` (macOS) or `sudo apt-get install jq` (Ubuntu)

3. **"Base branch does not exist"**

   - Fetch the base branch: `git fetch origin main`
   - Ensure you're comparing against the correct branch

4. **Rules not working as expected**
   - Check rule syntax with `jq` validation
   - Use `--verbose` flag for detailed logging
   - Test rules locally before pushing

### Debug Mode

Enable verbose logging for debugging:

```bash
VERBOSE=true ./run-codeguardian.sh main
```

### Validation

Validate your rules.json syntax:

```bash
jq . CodeGuardian/rules.json
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:

- Create an issue on GitHub
- Check the troubleshooting section
- Review existing issues and discussions
