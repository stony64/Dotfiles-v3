#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        collect-review.sh
# VERSION:     3.6.7
# DESCRIPTION: Dotfiles Aggregator for AI-Assisted Code Review
# AUTHOR:      Stony64
# CHANGES:     v3.6.7 - Add --include filter, statistics, improved output
# ------------------------------------------------------------------------------
# Purpose: Creates structured dump with explicit metadata for AI code review.
# Usage:   bash collect-review.sh [target-dir] [--all] [--include pattern]
# Output:  _exports/dotfiles_review_TIMESTAMP.txt
# ------------------------------------------------------------------------------

# ShellCheck configuration
# SC2312: Consider invoking separately - Intentional command substitution chaining
# shellcheck disable=SC2312

# Exit on error, undefined variables, pipe failures
set -euo pipefail

# --- CONFIGURATION ------------------------------------------------------------
# Script version (matches framework version for consistency)
readonly SCRIPT_VERSION="3.6.7"

# Project name (used in output filename)
readonly PROJECT_NAME="dotfiles"

# --- PARAMETER PARSING --------------------------------------------------------
# Target directory to scan (default: current directory)
TARGET_DIR=""

# Include all files regardless of exclusions (--all flag)
ALL_FILES=false

# Glob pattern for file inclusion filter (--include=pattern)
INCLUDE_PATTERN=""

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --all)
            ALL_FILES=true  # Disable exclusion filter
            ;;
        --include=*)
            # Extract pattern after '=' (e.g., --include=*.sh → *.sh)
            INCLUDE_PATTERN="${arg#*=}"
            ;;
        --help|-h)
            # Display usage information and exit
            cat <<EOF
Dotfiles Aggregator v${SCRIPT_VERSION}

Usage: $(basename "$0") [target-dir] [options]

Arguments:
  target-dir           Target directory to scan (default: current directory)

Options:
  --all                Include all files (ignore standard exclusions)
  --include=PATTERN    Only include files matching glob pattern (e.g., "*.sh")
  --help, -h           Show this help message

Examples:
  $(basename "$0")                           # Scan current directory
  $(basename "$0") /opt/dotfiles            # Scan specific directory
  $(basename "$0") --include="*.sh"         # Only shell scripts
  $(basename "$0") --include=".bash*"       # All bash dotfiles
  $(basename "$0") --all                    # Include all files

Pattern Examples:
  *.sh                 All .sh files
  .bash*               All .bash* files (bashrc, bashenv, etc.)
  home/*               All files in home/ directory
  *.{sh,bash}          All .sh and .bash files (brace expansion)

Output: _exports/${PROJECT_NAME}_review_TIMESTAMP.txt
EOF
            exit 0
            ;;
        -*)
            # Unknown option - show error and exit
            printf '\033[0;31mError: Unknown option: %s\033[0m\n' "$arg" >&2
            printf 'Use --help for usage information.\n' >&2
            exit 1
            ;;
        *)
            # Positional argument - treat as target directory
            [[ -z "$TARGET_DIR" ]] && TARGET_DIR="$arg"
            ;;
    esac
done

# Set default target directory to current working directory if not specified
TARGET_DIR="${TARGET_DIR:-$(pwd)}"

# --- VALIDATION ---------------------------------------------------------------
# Verify target directory exists (supports Windows paths via Git Bash)
if [[ ! -d "$TARGET_DIR" ]]; then
    printf '\033[0;31mError: Directory %s not found.\033[0m\n' "$TARGET_DIR" >&2
    exit 1
fi

# Create export directory in repository root
OUTPUT_DIR="${TARGET_DIR}/_exports"
mkdir -p "$OUTPUT_DIR" || {
    printf '\033[0;31mError: Failed to create output directory.\033[0m\n' >&2
    exit 1
}

# Generate filename with scope indicator and timestamp
# Scope indicates export mode: review (default), full-dump (--all), filtered (--include)
SCOPE="review"
[[ "$ALL_FILES" == true ]] && SCOPE="full-dump"
[[ -n "$INCLUDE_PATTERN" ]] && SCOPE="${SCOPE}-filtered"

# Timestamp format: YYYYMMDD_HHMMSS (sortable, filesystem-safe)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="${PROJECT_NAME}_${SCOPE}_${TIMESTAMP}.txt"
OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME}"

# --- EXCLUSION CONFIGURATION --------------------------------------------------
# Regex pattern for files/directories to skip (unless --all is used)
# Excludes: Git internals, build artifacts, binaries, images, archives
readonly EXCLUDE_REGEX='/(\.git|_exports|node_modules|test_sandbox|bin|obj|\.vs|\.vscode|dist|build)/|(\.bak$|\.png$|\.jpg$|\.jpeg$|\.pdf$|\.ico$|\.zip$|\.tar\.gz$|LICENSE$|\.lock$)'

# --- STATISTICS TRACKING ------------------------------------------------------
# Counters for export statistics (displayed in footer)
declare -i total_files=0      # Files successfully exported
declare -i total_lines=0      # Total lines of code
declare -i skipped_files=0    # Files skipped by filters

# --- FILTER HELPER ------------------------------------------------------------

# ------------------------------------------------------------------------------
# should_include_file
#
# Checks if file matches include pattern (if specified via --include).
# Uses glob matching for flexible pattern expansion (*.sh, .bash*, home/*).
# Case-based matching allows wildcards without regex complexity.
#
# Parameters: $1 - File path (relative to target directory)
# Returns: 0 if should include, 1 if should skip
# ------------------------------------------------------------------------------
should_include_file() {
    local file_path="$1"

    # No filter specified - include everything
    [[ -z "$INCLUDE_PATTERN" ]] && return 0

    # Check if filename matches glob pattern
    # Note: $INCLUDE_PATTERN is intentionally unquoted to enable glob expansion
    # Examples: *.sh, .bash*, home/* - all require glob matching
    # shellcheck disable=SC2254
    case "$file_path" in
        $INCLUDE_PATTERN)
            return 0  # File matches pattern
            ;;
        *)
            return 1  # File doesn't match pattern
            ;;
    esac
}

# --- EXPORT ENGINE ------------------------------------------------------------
# Main export block (redirect entire output to file)
{
    # Header with metadata for AI parsing
    echo "--- ${PROJECT_NAME^^} DUMP PROTOCOL V${SCRIPT_VERSION} ---"
    echo "METADATA | SOURCE: $TARGET_DIR | TIMESTAMP: $(date)"

    # Show active filters
    [[ -n "$INCLUDE_PATTERN" ]] && echo "FILTER | INCLUDE: $INCLUDE_PATTERN (glob pattern)"
    [[ "$ALL_FILES" == true ]] && echo "MODE | FULL DUMP (no exclusions)"
    echo "---------------------------------------------------------------------------"

    # Find all files in target directory
    # -type f: Files only (no directories)
    # -print0: Null-terminated output (handles filenames with spaces)
    # sort -z: Sort null-terminated input (consistent ordering)
    # read -r -d '': Read null-terminated strings
    find "$TARGET_DIR" -type f -print0 2>/dev/null | sort -z | while IFS= read -r -d '' file; do

        # Calculate relative path (remove target directory prefix)
        rel_path="${file#"$TARGET_DIR"/}"

        # Apply exclusion filter (unless --all flag is set)
        if [[ "$ALL_FILES" != true && "/$rel_path" =~ $EXCLUDE_REGEX ]]; then
            ((skipped_files++)) || true  # || true prevents set -e abort
            continue
        fi

        # Apply include filter (if --include pattern specified)
        # shellcheck disable=SC2310  # Function invocation in condition is intentional
        if ! should_include_file "$rel_path"; then
            ((skipped_files++)) || true
            continue
        fi

        # Extract file extension (everything after last dot)
        extension="${file##*.}"

        # Special handling for dotfiles without extension
        # Assign meaningful type based on filename patterns
        case "$rel_path" in
            *".bash"*) extension="bash" ;;
            *".gitattributes"*) extension="gitattributes" ;;
            *".gitignore"*) extension="gitignore" ;;
            ".shellcheckrc") extension="shellcheckrc" ;;
            ".editorconfig") extension="editorconfig" ;;
        esac

        # Count lines in file
        # Handles edge case: files without trailing newline
        # wc -l counts newline characters, so file without final \n shows count-1
        line_count=$(wc -l < "$file" 2>/dev/null || echo "0")

        # Structured block header for AI parsing
        # Format: [FILE_START] path="..." type="..." lines=N
        echo "[FILE_START] path=\"$rel_path\" type=\".$extension\" lines=$line_count"
        echo "--- CONTENT START ---"

        # Output complete file content (preserves formatting)
        cat "$file"

        # Clean block close (ensure newline before footer)
        printf '\n--- CONTENT END ---\n'
        echo "[FILE_END] path=\"$rel_path\""
        echo "---------------------------------------------------------------------------"

        # Update statistics counters
        ((total_files++)) || true       # || true prevents set -e abort when count=0
        ((total_lines += line_count)) || true
    done

    # Statistics footer (summary of export)
    echo "--- STATISTICS ---"
    echo "Total Files:   $total_files"
    echo "Total Lines:   $total_lines"
    echo "Skipped Files: $skipped_files"
    echo "Export Time:   $(date)"
    echo "--- END OF DUMP ---"
} > "$OUTPUT_FILE"  # Redirect entire block to output file

# --- OUTPUT & INTEGRATION -----------------------------------------------------
# Display success message with color (green checkmark)
printf '\033[0;32m✓ Export successful: %s\033[0m\n' "$FILENAME"
printf '\033[0;36m  Format: v%s (Structured Framework Tag System)\033[0m\n' "$SCRIPT_VERSION"
printf '  Location: %s\n' "$OUTPUT_FILE"

# Show statistics inline
printf '  Files: %d | Lines: %d' "$total_files" "$total_lines"
[[ $skipped_files -gt 0 ]] && printf ' | Skipped: %d' "$skipped_files"
printf '\n'

# Display file size (human-readable format)
if command -v du >/dev/null 2>&1; then
    file_size=$(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1)
    printf '  Size: %s\n' "$file_size"
fi

# Clipboard integration (multi-platform support)
# Automatically copy content to clipboard if tool is available
if command -v clip.exe >/dev/null 2>&1; then
    # Windows (Git Bash/WSL) - uses native Windows clipboard
    clip.exe < "$OUTPUT_FILE"
    printf '\033[0;32m✓ Content copied to Windows clipboard.\033[0m\n'
elif command -v xclip >/dev/null 2>&1; then
    # Linux X11 - requires xclip package (apt install xclip)
    xclip -selection clipboard < "$OUTPUT_FILE"
    printf '\033[0;32m✓ Content copied to X11 clipboard.\033[0m\n'
elif command -v pbcopy >/dev/null 2>&1; then
    # macOS - native clipboard command
    pbcopy < "$OUTPUT_FILE"
    printf '\033[0;32m✓ Content copied to macOS clipboard.\033[0m\n'
fi

# Explorer integration (Windows/Git Bash/WSL only)
# Opens export directory in Windows Explorer for easy access
if command -v explorer.exe >/dev/null 2>&1; then
    # Convert Unix path to Windows path if needed (cygpath in Git Bash)
    explorer.exe "$(cygpath -w "$OUTPUT_DIR" 2>/dev/null || echo "$OUTPUT_DIR")"
fi
