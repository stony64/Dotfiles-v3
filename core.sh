#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         core.sh
# VERSION:      3.3.0
# DESCRIPTION:  Zentrale Framework-Bibliothek für Validierung, UI und System.
# TYPE:         SOURCED MODULE
# AUTHOR:       Stony64
# ------------------------------------------------------------------------------
# shellcheck shell=bash disable=SC2034  # DF_* vars assigned later

# --- GUARD (P1) ---------------------------------------------------------------
[[ -n "${DF_CORE_LOADED:-}" ]] && return 0
readonly DF_CORE_LOADED=1

# --- KONFIGURATION ------------------------------------------------------------
export DF_PROJECT_VERSION="3.3.0"
export DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"

# --- UI KONSTANTEN ------------------------------------------------------------
DF_C_RED=$'\033[31m'
DF_C_GREEN=$'\033[32m'
DF_C_YELLOW=$'\033[33m'
DF_C_BLUE=$'\033[34m'
DF_C_RESET=$'\033[0m'

DF_SYM_OK='[OK]'
DF_SYM_ERR='[ERR]'
DF_SYM_WARN='[!]'

# --- 1. LOGGING & UI (P2) -----------------------------------------------------
df_log_info() { printf '%b%s%b\n' "$DF_C_BLUE" "--> $*" "$DF_C_RESET"; }
df_log_success() { printf '%b%s%b %s\n' "$DF_C_GREEN" "$DF_SYM_OK" "$DF_C_RESET" "$*"; }
df_log_warn() { printf '%b%s%b %s\n' "$DF_C_YELLOW" "$DF_SYM_WARN" "$DF_C_RESET" "$*"; }
df_log_error() { printf '%b%s%b %s\n' "$DF_C_RED" "$DF_SYM_ERR" "$DF_C_RESET" "$*" >&2; }

# --- 2. VALIDIERUNG & SYSTEM (P0/P1) ------------------------------------------
df_check_root() {
    if [[ $EUID -ne 0 ]]; then
        df_log_warn "Root-Rechte empfohlen: sudo $(basename "${BASH_SOURCE[1]:-${0}}")"
        return 1
    fi
}

# ZWECK: Validiert "echte" User (UID 0 oder >= 1000).
df_is_real_user() {
    local target_user="$1" uid
    uid=$(getent passwd "$target_user" | cut -d: -f3) || return 1
    [[ "$uid" -eq 0 || "$uid" -ge 1000 ]]
}

# ZWECK: Listet alle relevanten User (sortiert, nologin-frei).
df_list_real_users() {
    getent passwd | awk -F: '$3==0 || ($3>=1000 && $7!~/nologin/ && $7!~/false/) {print $1}' | sort -u
}

# ZWECK: Ermittelt sicher das Home-Verzeichnis. (FIX SC2015)
df_get_user_home() {
    local target_user="$1" home
    home=$(getent passwd "$target_user" | cut -d: -f6)

    if [[ -n "$home" && -d "$home" ]]; then
        printf '%s' "$home"
    else
        df_log_error "Home nicht gefunden für: $target_user"
        return 1
    fi
}

# --- 3. DATEI-OPERATIONEN & BACKUP (P1/P3) ------------------------------------
df_backup_create() {
    local user="$1" home backup_dir timestamp backup_file
    home=$(df_get_user_home "$user") || return 1
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_dir="${DF_REPO_ROOT}/backup/${user}_${timestamp}"
    backup_file="${backup_dir}/${user}_dotfiles.tar.gz"

    mkdir -p "$backup_dir"
    df_log_info "Backup → $backup_dir"

    # Kritische Dotfiles backup (graceful)
    # Verwende ein Array für die Liste, um SC2015/SC2046 Probleme zu vermeiden
    local files=(.bashrc .profile .bash_profile .vimrc .gitconfig .tmux.conf .ssh/config .config/git/config)

    # Filtere nur existierende Dateien für tar, um stderr-Müll zu vermeiden
    local existing_files=()
    for f in "${files[@]}"; do
        [[ -f "${home}/$f" ]] && existing_files+=("$f")
    done

    if [[ ${#existing_files[@]} -gt 0 ]]; then
        tar -czf "$backup_file" -C "$home" "${existing_files[@]}" 2>/dev/null
        df_log_success "Backup erstellt: $(du -sh "$backup_file" | cut -f1)"
    else
        df_log_warn "Keine relevanten Dotfiles für $user gefunden."
    fi
}

# ZWECK: Lädt alle .sh Module aus lib/.
df_load_modules() {
    local mod_dir="${DF_REPO_ROOT}/lib" mod
    [[ -d "$mod_dir" ]] || return 0
    # Globbing sicher handhaben (verhindert Fehler, wenn lib/ leer ist)
    shopt -s nullglob
    for mod in "$mod_dir"/*.sh; do
        df_log_info "Lade Modul: $(basename "$mod")"
        # shellcheck source=/dev/null
        source "$mod"
    done
    shopt -u nullglob
}

# ZWECK: Setzt Owner/Gruppe rekursiv.
df_set_owner() {
    local target_path="$1" target_user="$2" target_group
    [[ ! -e "$target_path" ]] && return 1
    target_group=$(id -gn "$target_user")
    chown -R "${target_user}:${target_group}" "$target_path"
    df_log_success "Owner gesetzt: ${target_user}:${target_group} → $target_path"
}

# ZWECK: Erstellt Symlinks mit Backup-Logik (atomic).
df_create_link() {
    local src="$1" dest="$2" backup_suffix
    [[ ! -e "$src" ]] && { df_log_error "Source fehlt: $src"; return 1; }

    backup_suffix=".bak_$(date +%Y%m%d_%H%M%S)"

    # Falls dest existiert und kein Link ist -> verschieben
    if [[ -e "$dest" && ! -L "$dest" ]]; then
        mv "$dest" "${dest}${backup_suffix}"
        df_log_warn "Bestand gesichert: ${dest}${backup_suffix}"
    # Falls dest ein falscher Link ist -> entfernen
    elif [[ -L "$dest" ]]; then
        local current_target
        current_target=$(readlink "$dest")
        if [[ "$current_target" != "$src" ]]; then
            rm "$dest"
        else
            df_log_info "Link bereits korrekt: $dest"
            return 0
        fi
    fi

    ln -sf "$src" "$dest"
    df_log_success "Symlink erstellt: $dest"
}
