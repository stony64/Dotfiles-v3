#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        lib/df-backup.sh
# VERSION:     3.6.6
# DESCRIPTION: Backup Module for Automated User Configuration Snapshots
# TYPE:        Sourced Module (requires core.sh)
# AUTHOR:      Stony64
# CHANGES:     v3.6.6 - Fixed cleanup logic, robust tar handling
# ------------------------------------------------------------------------------

# ShellCheck configuration (ignore missing source file, allow unused variables)
# shellcheck source=/dev/null disable=SC2034

# --- IDEMPOTENCY GUARD --------------------------------------------------------
# Prevents duplicate loading if module is sourced multiple times
[[ -n "${DF_BACKUP_LOADED:-}" ]] && return 0
readonly DF_BACKUP_LOADED=1

# --- BOOTSTRAP HINTS ----------------------------------------------------------
# Inform ShellCheck about external variables from core.sh
# Sets default if core.sh hasn't been loaded yet
DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"

# --- CONFIGURATION ------------------------------------------------------------
# Repository backup directory (stores all user snapshots)
readonly DF_BACKUP_DIR="${DF_REPO_ROOT}/_backups"

# Number of backup snapshots to retain per user (FIFO rotation)
readonly DF_BACKUP_RETENTION=5  # Keep last N backups per user

# --- BACKUP CREATION ----------------------------------------------------------

# ------------------------------------------------------------------------------
# df_backup_create
#
# Creates compressed snapshot of user's relevant dotfiles.
# Stores tarball in repository's _backups/<user>/ directory.
# Includes: .bashrc, .bash_profile, .profile, .config/, and framework files.
# Automatically cleans up old backups after successful creation.
#
# Tarball format: snapshot_YYYYMMDD_HHMMSS.tar.gz
#
# Parameters:
#   $1 - Username to backup
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
df_backup_create() {
    local user_name="${1:?Usage: df_backup_create <username>}"
    local home_directory
    local backup_directory
    local backup_file_name
    local timestamp
    local -a backup_targets      # Files/dirs to backup (relative paths)
    local -a existing_targets    # Filtered list (only existing items)

    # Validate user exists and get home directory
    if ! home_directory=$(get_user_home "$user_name" 2>/dev/null); then
        df_log_error "Backup failed: Home directory not found for $user_name"
        return 1
    fi

    # Setup backup directory structure: _backups/<username>/
    backup_directory="${DF_BACKUP_DIR}/${user_name}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file_name="${backup_directory}/snapshot_${timestamp}.tar.gz"

    # Create backup directory if it doesn't exist
    if [[ ! -d "$backup_directory" ]]; then
        if ! mkdir -p "$backup_directory"; then
            df_log_error "Failed to create backup directory: $backup_directory"
            return 1
        fi
        # Set secure permissions if running as root
        if [[ $EUID -eq 0 ]]; then
            chown root:root "$backup_directory" 2>/dev/null || true
        fi
    fi

    df_log_info "Creating backup for $user_name..."

    # Define backup targets (relative to home directory)
    # Add more dotfiles here as needed
    backup_targets=(
        ".bashrc"
        ".bash_profile"
        ".profile"
        ".bashenv"
        ".bashaliases"
        ".bashfunctions"
        ".bashprompt"
        ".nanorc"
        ".config"          # Directory (includes subdirectories)
    )

    # Filter to only existing targets (prevents tar errors on missing files)
    existing_targets=()
    local target
    for target in "${backup_targets[@]}"; do
        if [[ -e "${home_directory}/${target}" ]]; then
            existing_targets+=("$target")
        fi
    done

    # Verify we have something to backup
    if [[ ${#existing_targets[@]} -eq 0 ]]; then
        df_log_warn "No backup targets found for $user_name"
        return 1
    fi

    # Create compressed tarball (P0: Data integrity)
    # tar flags: -c create, -z gzip, -f file
    # -C: Change to home_directory before archiving (stores relative paths)
    if tar -czf "$backup_file_name" -C "$home_directory" "${existing_targets[@]}" 2>/dev/null; then
        # Show human-readable backup size
        local backup_size
        backup_size=$(du -h "$backup_file_name" | cut -f1)
        df_log_success "Backup created: $(basename "$backup_file_name") (${backup_size})"

        # Automatic cleanup after successful backup (keep last N)
        df_backup_cleanup "$user_name"

        return 0
    else
        df_log_error "Backup failed for $user_name"
        # Remove incomplete backup file to prevent corruption
        rm -f "$backup_file_name" 2>/dev/null
        return 1
    fi
}

# --- BACKUP CLEANUP -----------------------------------------------------------

# ------------------------------------------------------------------------------
# df_backup_cleanup
#
# Removes old backups for specified user, keeping only the last N snapshots.
# Retention count is configured via DF_BACKUP_RETENTION (default: 5).
# Sorts by filename (timestamp-based) to determine age.
# Deletes oldest backups first (FIFO rotation).
#
# Parameters:
#   $1 - Username to clean up backups for
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
df_backup_cleanup() {
    local user_name="${1:?Usage: df_backup_cleanup <username>}"
    local backup_directory="${DF_BACKUP_DIR}/${user_name}"
    local -a backup_files      # Array of backup file paths
    local file_count
    local delete_count

    # Skip if backup directory doesn't exist (nothing to clean)
    [[ ! -d "$backup_directory" ]] && return 0

    # Get list of backup files sorted by name (oldest first)
    # Filename format: snapshot_YYYYMMDD_HHMMSS.tar.gz (naturally sortable)
    mapfile -t backup_files < <(find "$backup_directory" -name 'snapshot_*.tar.gz' -type f | sort)

    file_count=${#backup_files[@]}

    # Check if cleanup is needed (keep last N backups)
    if [[ $file_count -le $DF_BACKUP_RETENTION ]]; then
        return 0  # Not enough backups to clean
    fi

    # Calculate how many old backups to delete
    delete_count=$((file_count - DF_BACKUP_RETENTION))

    df_log_info "Cleaning up old backups for $user_name (keeping last ${DF_BACKUP_RETENTION})..."

    # Delete oldest backups (array is sorted, so delete from start)
    local i
    for (( i=0; i<delete_count; i++ )); do
        if rm -f "${backup_files[$i]}" 2>/dev/null; then
            df_log_info "Removed: $(basename "${backup_files[$i]}")"
        else
            df_log_warn "Failed to remove: $(basename "${backup_files[$i]}")"
        fi
    done

    df_log_success "Cleanup complete: removed $delete_count old backup(s)"
    return 0
}

# --- BACKUP RESTORATION (Optional) --------------------------------------------

# ------------------------------------------------------------------------------
# df_backup_list
#
# Lists all available backups for specified user with sizes.
# Sorted by date (newest first) for easier selection.
#
# Parameters:
#   $1 - Username
# Returns: 0 if backups found, 1 if none
# ------------------------------------------------------------------------------
df_backup_list() {
    local user_name="${1:?Usage: df_backup_list <username>}"
    local backup_directory="${DF_BACKUP_DIR}/${user_name}"

    # Check if backup directory exists
    if [[ ! -d "$backup_directory" ]]; then
        df_log_warn "No backups found for $user_name"
        return 1
    fi

    df_log_info "Available backups for $user_name:"

    # Get list of backup files sorted by date (newest first)
    local -a backup_files
    mapfile -t backup_files < <(find "$backup_directory" -name 'snapshot_*.tar.gz' -type f | sort -r)

    # Verify backup files exist
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        df_log_warn "No backup files found"
        return 1
    fi

    # Print each backup with human-readable size
    local file
    local size
    for file in "${backup_files[@]}"; do
        size=$(du -h "$file" | cut -f1)
        printf "  - %s (%s)\n" "$(basename "$file")" "$size"
    done

    return 0
}

# ------------------------------------------------------------------------------
# df_backup_restore
#
# Restores specified backup snapshot to user's home directory.
# Creates .bak_<timestamp> copies of existing files before overwriting.
# INTERACTIVE: Prompts for confirmation before restoration.
#
# Parameters:
#   $1 - Username
#   $2 - Snapshot filename (e.g., snapshot_20260216_102530.tar.gz)
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
df_backup_restore() {
    local user_name="${1:?Usage: df_backup_restore <username> <snapshot>}"
    local snapshot_name="${2:?Usage: df_backup_restore <username> <snapshot>}"
    local backup_file="${DF_BACKUP_DIR}/${user_name}/${snapshot_name}"
    local home_directory

    # Verify backup file exists
    if [[ ! -f "$backup_file" ]]; then
        df_log_error "Backup file not found: $snapshot_name"
        return 1
    fi

    # Get user's home directory
    if ! home_directory=$(get_user_home "$user_name" 2>/dev/null); then
        df_log_error "Home directory not found for $user_name"
        return 1
    fi

    # Interactive confirmation (safety measure)
    df_log_warn "About to restore: $snapshot_name → $home_directory"
    printf "Existing files will be backed up. Continue? [y/N] "
    read -r confirmation

    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        df_log_info "Restore cancelled by user"
        return 1
    fi

    # Extract tarball to home directory
    # tar flags: -x extract, -z gzip, -f file, -C change directory
    # --backup=numbered: Create .~N~ backups of existing files
    if tar -xzf "$backup_file" -C "$home_directory" --backup=numbered 2>/dev/null; then
        df_log_success "Backup restored successfully"
        df_log_info "Existing files backed up with .~N~ suffix"
        return 0
    else
        df_log_error "Restore failed"
        return 1
    fi
}
