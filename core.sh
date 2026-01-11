#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         core.sh
# VERSION:      3.1.1
# DESCRIPTION:  Zentrale Framework-Bibliothek für Validierung, UI und System.
# TYPE:         SOURCED MODULE
# ------------------------------------------------------------------------------

# --- GUARD (P1) ---------------------------------------------------------------
[[ -n "${DF_CORE_LOADED:-}" ]] && return 0
readonly DF_CORE_LOADED=1

# --- KONFIGURATION ------------------------------------------------------------
export DF_PROJECT_VERSION="3.1.1"
export DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"

# --- UI KONSTANTEN ------------------------------------------------------------
readonly DF_C_RED=$'\033[31m'
readonly DF_C_GREEN=$'\033[32m'
readonly DF_C_YELLOW=$'\033[33m'
readonly DF_C_BLUE=$'\033[34m'
readonly DF_C_RESET=$'\033[0m'

readonly DF_SYM_OK='[OK]'
readonly DF_SYM_ERR='[ERR]'
readonly DF_SYM_WARN='[!]'

# --- 1. LOGGING & UI (P2) -----------------------------------------------------

# ZWECK: Standard Info-Meldung ausgeben.
# PARAM: $@ (String) - Nachricht.
# RETURN: 0
df_log_info() { printf '%b-->%b %s\n' "$DF_C_BLUE" "$DF_C_RESET" "$*"; }

# ZWECK: Erfolgsmeldung ausgeben.
# PARAM: $@ (String) - Nachricht.
# RETURN: 0
df_log_success() { printf '%b%s%b %s\n' "$DF_C_GREEN" "$DF_SYM_OK" "$DF_C_RESET" "$*"; }

# ZWECK: Fehlermeldung nach stderr ausgeben.
# PARAM: $@ (String) - Nachricht.
# RETURN: 0
df_log_error() { printf '%b%s%b %s\n' "$DF_C_RED" "$DF_SYM_ERR" "$DF_C_RESET" "$*" >&2; }

# --- 2. VALIDIERUNG & SYSTEM (P0/P1) ------------------------------------------

# ZWECK: Prüft auf Root-Rechte (EUID 0).
# RETURN: 0 wenn Root, sonst 1.
df_check_root() { [[ $EUID -eq 0 ]]; }

# ZWECK: Validiert "echte" User (UID 0 oder >= 1000).
# PARAM: $1 (String) - Username.
# RETURN: 0 bei Erfolg, 1 wenn System-User oder ungültig.
df_is_real_user() {
    local target_user="$1"
    local uid
    uid=$(getent passwd "$target_user" | cut -d: -f3) || return 1
    [[ "$uid" -eq 0 || "$uid" -ge 1000 ]]
}

# ZWECK: Listet alle relevanten User für --all (UID 0 & >= 1000).
# RETURN: 0 (stdout Liste der User).
df_list_real_users() {
    getent passwd | awk -F: '$3 == 0 || $3 >= 1000 {print $1}' | grep -v "nobody"
}

# ZWECK: Ermittelt sicher das Home-Verzeichnis eines Users.
# PARAM: $1 (String) - Username.
# RETURN: 0 (stdout Pfad), 1 wenn Pfad nicht existiert.
df_get_user_home() {
    local target_user="$1"
    local home
    home=$(getent passwd "$target_user" | cut -d: -f6)
    if [[ -n "$home" && -d "$home" ]]; then
        printf '%s' "$home"
        return 0
    fi
    return 1
}

# --- 3. DATEI-OPERATIONEN & MODUL-LOADING (P1/P3) -----------------------------

# ZWECK: Lädt alle .sh Module aus dem lib/ Ordner.
# RETURN: 0
df_load_modules() {
    local mod_dir="${DF_REPO_ROOT}/lib"
    local mod
    if [[ -d "$mod_dir" ]]; then
        for mod in "$mod_dir"/*.sh; do
            [[ -f "$mod" ]] && source "$mod"
        done
    fi
}

# ZWECK: Setzt Owner/Gruppe rekursiv basierend auf dem User.
# PARAM: $1 (Path) - Zielpfad, $2 (String) - User.
# RETURN: 0 bei Erfolg.
df_set_owner() {
    local target_path="$1"
    local target_user="$2"
    local target_group
    [[ ! -e "$target_path" ]] && return 1
    target_group=$(id -gn "$target_user")
    chown -R "${target_user}:${target_group}" "$target_path"
}

# ZWECK: Erstellt Symlinks mit Backup-Logik bei echten Dateien (P1).
# PARAM: $1 (Source), $2 (Destination).
# RETURN: 0 bei Erfolg.
df_create_link() {
    local src="$1" dest="$2"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
        mv "$dest" "${dest}.bak_$(date +%Y%m%d_%H%M%S)"
    fi
    ln -sf "$src" "$dest"
}
