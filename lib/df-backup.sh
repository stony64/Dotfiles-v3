#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         lib/df-backup.sh
# VERSION:      3.1.1
# DESCRIPTION:  Backup-Modul für automatisierte Snapshots der User-Konfiguration.
# TYPE:         SOURCED MODULE
# ------------------------------------------------------------------------------

# --- GUARD (P1) ---------------------------------------------------------------
[[ -n "${DF_BACKUP_LOADED:-}" ]] && return 0
readonly DF_BACKUP_LOADED=1

# --- BOOTSTRAP HINTS (SC2154 Fix) ---------------------------------------------
# ShellCheck über externe Variablen informieren, die aus core.sh stammen.
# shellcheck disable=SC2034
DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"

# --- 1. BACKUP-LOGIK (P0/P1) --------------------------------------------------

# ZWECK: Erstellt ein komprimiertes Backup der bestehenden Dotfiles eines Users.
# PARAM: $1 (String) - Ziel-Username.
# RETURN: 0 bei Erfolg, 1 bei schwerwiegenden Fehlern.
df_backup_create() {
    local user="$1"
    local home_dir backup_dir backup_file timestamp

    # 1. Validierung & Pfad-Setup
    home_dir=$(df_get_user_home "$user") || {
        df_log_error "Backup-Fehler: Home für $user nicht gefunden."
        return 1
    }

    # Backup-Verzeichnis im Repository (zentral)
    backup_dir="${DF_REPO_ROOT}/_backups/${user}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="${backup_dir}/snapshot_${timestamp}.tar.gz"

    # 2. Struktur sicherstellen (P1)
    if [[ ! -d "$backup_dir" ]]; then
        # -p ist idempotent: erstellt Pfad nur wenn nötig
        mkdir -p "$backup_dir"
        # Falls als root ausgeführt, Owner auf Framework-Standard (root)
        [[ $EUID -eq 0 ]] && chown root:root "$backup_dir"
    fi

    df_log_info "Erstelle Sicherheits-Backup für $user..."

    # 3. Backup ausführen (P0 - Datenintegrität)
    # Wir sichern gezielt die XDG-Struktur und Bash-Konfigs
    if ! tar -czf "$backup_file" -C "$home_dir" .bashrc .config/ 2>/dev/null; then
        df_log_warn "Einige Pfade für $user fehlten beim Backup (Teil-Snapshot erstellt)."
    fi

    if [[ -f "$backup_file" ]]; then
        df_log_success "Backup erstellt: $(basename "$backup_file")"
        return 0
    else
        df_log_error "Backup-Datei konnte nicht geschrieben werden!"
        return 1
    fi
}

# ZWECK: Bereinigt alte Backups (behält die letzten 5).
# PARAM: $1 (String) - Ziel-Username.
# RETURN: 0
df_backup_cleanup() {
    local user="$1"
    local backup_dir="${DF_REPO_ROOT}/_backups/${user}"
    local count

    [[ ! -d "$backup_dir" ]] && return 0

    # P3: Wartbarkeit des Speicherplatzes
    # shellcheck disable=SC2012
    count=$(ls -1 "${backup_dir}"/*.tar.gz 2>/dev/null | wc -l)
    if [[ "$count" -gt 5 ]]; then
        df_log_info "Bereinige alte Backups für $user (Limit: 5)..."
        # shellcheck disable=SC2012
        ls -t "${backup_dir}"/*.tar.gz | tail -n +6 | xargs rm -f
    fi
}
