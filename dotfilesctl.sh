#!/usr/bin/env bash
# --------------------------------------------------------------------------
# FILE:           dotfilesctl.sh
# VERSION:        3.8.0
# DESCRIPTION:    Dotfiles Framework Controller (Multi-User + Config Fixes)
# AUTHOR:         Stony64
# LAST UPDATE:    2026-03-01
# CHANGES:        3.8.0 - Multi-User (--all), .nanorc aus home/, home/config/ → ~/.config/
# --------------------------------------------------------------------------

# Exit on error, undefined variables, pipe failures
set -euo pipefail

# --- BOOTSTRAP ----------------------------------------------------------------
SCRIPTDIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
readonly SCRIPTDIR

if [[ ! -f "${SCRIPTDIR}/core.sh" ]]; then
    printf '\033[31m[FATAL]\033[0m core.sh not found\n' >&2
    exit 1
fi

source "${SCRIPTDIR}/core.sh" || exit 1

# --- CONFIGURATION ------------------------------------------------------------
readonly DOTFILES_DIR="${DF_REPO_ROOT:-${SCRIPTDIR}}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly TIMESTAMP
readonly BACKUP_DIR="${HOME}/.dotfiles_backups"

# --- HELPER FUNCTIONS ---------------------------------------------------------
show_version() {
    printf 'Dotfiles Framework v%s\n' "${DF_PROJECT_VERSION}"
}

show_usage() {
    cat <<EOF
Dotfiles Framework Controller v${DF_PROJECT_VERSION}

Usage: $(basename "$0") <command> [options]

Commands:
  backup [--all]        Backup current/all real users
  install [--all USER]  Deploy for current/all/specific user
  reinstall [--all]     Remove + redeploy
  status [--all]        Check all users
  clean [--backup]      Remove symlinks/backups
  version               Show version
  help                  This help

Multi-User: --all = alle realen User (UID 0/>=1000)
Examples:
  sudo dctl install --all
  dctl install --user ston64
  dctl status --all

Repository: ${DOTFILES_DIR}
EOF
}

# --- CORE FUNCTIONS -----------------------------------------------------------
backup_dotfiles() {  # Unchanged
    local backup_root="${BACKUP_DIR}"
    local timestamp="${TIMESTAMP}"
    local current_backup_dir="${backup_root}/${timestamp}"

    if ! command -v tar >/dev/null 2>&1; then
        df_log_error "tar not found - backup skipped"
        return 1
