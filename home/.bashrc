#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        home/.bashrc
# VERSION:     3.6.7
# DESCRIPTION: Main Configuration with Deterministic Module Loading
# AUTHOR:      Stony64
# CHANGES:     v3.6.7 - Add stty -ixon for editor shortcuts
# ------------------------------------------------------------------------------

# ShellCheck configuration (ignore missing source file, allow unused variables)
# shellcheck source=/dev/null disable=SC2034

# --- INTERACTIVE CHECK --------------------------------------------------------
# Exit immediately if not running interactively
# $- contains shell options: 'i' = interactive mode
# Non-interactive shells (scripts, scp, rsync) skip initialization
[[ $- != *i* ]] && return

# --- PROJECT ENVIRONMENT ------------------------------------------------------
# Repository root directory (overridable via environment)
export DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"

# Core framework library path (single source of truth)
export DF_CORE="${DF_REPO_ROOT}/core.sh"

# --- CORE LIBRARY LOADING -----------------------------------------------------
# Load core framework (logging, colors, utilities)
# Implements graceful fallback if core.sh is missing
if [[ -f "$DF_CORE" ]]; then
    # shellcheck source=/dev/null
    source "$DF_CORE"

    # Verify core.sh loaded correctly (sets DF_PROJECT_VERSION)
    if [[ -z "${DF_PROJECT_VERSION:-}" ]]; then
        printf '\033[33m[WARN]\033[0m DF_PROJECT_VERSION not set by core.sh\n' >&2
    fi
else
    # Fallback: Core library not found (broken installation)
    printf '\033[31m[ERR]\033[0m Core library not found: %s\n' "$DF_CORE" >&2
    printf '\033[33m[INFO]\033[0m Continuing with limited functionality...\n' >&2

    # Define minimal logging functions for error reporting
    if ! command -v df_log_info >/dev/null 2>&1; then
        df_log_info()  { printf '\033[34m-->\033[0m %s\n' "$*"; }
        df_log_error() { printf '\033[31m[ERR]\033[0m %s\n' "$*" >&2; }
        df_log_warn()  { printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
    fi

    # Set fallback version identifier
    export DF_PROJECT_VERSION="${DF_PROJECT_VERSION:-3.6.7-fallback}"
fi

# ==============================================================================
# TERMINAL: Disable XON/XOFF Flow Control
# ==============================================================================
# Enables Ctrl+S and Ctrl+Q as normal shortcuts in editors (nano, vim, less)
#
# Background:
#   XON/XOFF flow control is a legacy feature from serial terminal days.
#   Ctrl+S (XOFF) paused terminal output, Ctrl+Q (XON) resumed it.
#   This is rarely needed on modern systems and conflicts with editor shortcuts.
#
# Impact:
#   - Ctrl+S in nano: Save file (Write Out)
#   - Ctrl+Q in nano: Quit editor
#   - Ctrl+S in vim:  Can be mapped to save
#   - Ctrl+S in less: Forward search
#
# Disable with: stty ixon (to re-enable flow control if needed)
# ==============================================================================
stty -ixon 2>/dev/null  # -ixon = disable flow control, 2>/dev/null = suppress errors

# --- DETERMINISTIC MODULE LOADER ----------------------------------------------
# Load modules in fixed order to respect dependencies:
#   1. ENV         → Environment variables and shell options (PATH, EDITOR, etc.)
#   2. FUNCTIONS   → Bash functions (archive, search, network utilities)
#   3. ALIASES     → Command aliases and shortcuts (ll, la, grep colors)
#   4. PROMPT      → PS1 configuration with Git awareness and exit codes
#   5. MAINTENANCE → System maintenance helpers (apt, zfs, locate updates)
#
# Order matters: Later modules may depend on earlier ones
# (e.g., prompt uses colors from ENV, aliases use functions)

declare -a df_modules=(
    ".bashenv"        # Environment: PATH, EDITOR, colors, history config
    ".bashfunctions"  # Functions: extract, mkcd, ff, ft, myip, hg
    ".bashaliases"    # Aliases: ll, la, grep, git shortcuts
    ".bashprompt"     # Prompt: PS1 with Git branch, exit code, colors
    ".bashwartung"    # Maintenance: au, au-full system update commands
)

# Load each module in order
for mod_name in "${df_modules[@]}"; do
    mod_path="${HOME}/${mod_name}"

    # Check if module exists and is readable
    if [[ -r "$mod_path" ]]; then
        # shellcheck source=/dev/null
        source "$mod_path" || {
            # Warn on load failure but continue (non-critical)
            printf '\033[33m[WARN]\033[0m Failed to load: %s\n' "$mod_name" >&2
        }
    else
        # Silent skip for optional modules (e.g., .bashwartung on non-Proxmox)
        # Colon (:) is a no-op command in bash
        :
    fi
done

# --- FRAMEWORK UTILITIES ------------------------------------------------------

# ------------------------------------------------------------------------------
# reload_shell
#
# Reloads shell configuration by re-sourcing .bashrc.
# Useful after editing configuration files to apply changes immediately.
# Alternative to closing and reopening terminal.
#
# Limitations:
#   - Cannot unset previously set variables
#   - Cannot undefine functions (only overwrite)
#   - May cause issues if configuration changed incompatibly
#
# Parameters: None
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
reload_shell() {
    local bashrc_path="${HOME}/.bashrc"

    # Verify .bashrc exists and is readable
    if [[ ! -r "$bashrc_path" ]]; then
        printf '\033[31m[ERR]\033[0m .bashrc not found or not readable\n' >&2
        return 1
    fi

    # Re-source the configuration
    # shellcheck source=/dev/null
    if source "$bashrc_path"; then
        printf '\033[32m[OK]\033[0m Shell configuration reloaded\n'
        return 0
    else
        printf '\033[31m[ERR]\033[0m Failed to reload shell configuration\n' >&2
        return 1
    fi
}

# Convenience alias for shorter command
alias reload='reload_shell'

# ------------------------------------------------------------------------------
# dctl (Dotfiles Controller Alias)
#
# Security fallback: Only create alias if dctl is not already in PATH.
# Prevents accidental override of installed dctl binary.
#
# Background:
#   - Checks if 'dctl' exists as external command
#   - If not found: Creates alias to dotfilesctl.sh script
#   - If found: Skips alias creation (uses system binary)
#
# Usage:
#   dctl status      → Check dotfiles symlink integrity
#   dctl reinstall   → Remove and redeploy all dotfiles
#   dctl backup      → Create timestamped backup
# ------------------------------------------------------------------------------
if ! command -v dctl >/dev/null 2>&1; then
    # dctl not in PATH - create alias to script
    # sudo: Required for system-wide symlink management
    alias dctl='sudo "${DF_REPO_ROOT}/dotfilesctl.sh"'
fi

# ------------------------------------------------------------------------------
# tools
#
# Displays all available tools within the dotfiles framework.
# Shows framework version and quick reference for common commands.
# Comprehensive help system for discovering available utilities.
#
# Categories:
#   - Core Commands: Framework management (reload, dctl)
#   - Utilities: File/text search, network, archives
#   - System: Maintenance commands (APT, ZFS, locate)
#   - Git Shortcuts: Common git operations
#
# Parameters: None
# Returns: None
# ------------------------------------------------------------------------------
tools() {
    local version="${DF_PROJECT_VERSION:-unknown}"

    # Load colors from framework or use ANSI codes directly
    local color_blue="${DF_C_BLUE:-\033[34m}"
    local color_reset="${DF_C_RESET:-\033[0m}"

    # Print header with framework version
    printf '\n%s=== Dotfiles Framework v%s ===%s\n\n' "$color_blue" "$version" "$color_reset"

    # Main help text (heredoc for multi-line output)
    cat <<'EOF'
Core Commands:
  reload       → Reload shell configuration
  dctl         → Dotfiles management utility
  tools        → Show this help

Utilities:
  myip         → Show local and public IP addresses
  path         → Display formatted $PATH
  hg <term>    → Search command history
  ff <name>    → Find files by name
  ft <text>    → Find text in files
  mkcd <dir>   → Create directory and cd into it
  extract <f>  → Universal archive extractor

System (requires root):
  au           → Quick APT update
  au-full      → Full system maintenance (APT + ZFS + Locate)

Git Shortcuts:
  st           → git status
  co           → git checkout
  br           → git branch -v
  cm <msg>     → git commit -m "msg"
  lg           → Pretty git log (last 15 commits)

EOF

    # Show dotfiles status if dctl is available
    if command -v dctl >/dev/null 2>&1; then
        printf '%sStatus Check:%s\n' "$color_blue" "$color_reset"
        # Run status check (suppress errors if not root)
        dctl status 2>/dev/null || printf '  (Run: sudo dctl status)\n'
    fi

    printf '\n'
}

# --- FINALIZATION -------------------------------------------------------------
# Greeting message after all modules are loaded
# Only shown if core framework was loaded successfully (df_log_info available)
if command -v df_log_info >/dev/null 2>&1; then
    df_log_info "Framework v${DF_PROJECT_VERSION} loaded. Type 'tools' for help."
fi
