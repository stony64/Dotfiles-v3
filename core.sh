#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:          core.sh
# VERSION:       3.4.0
# DESCRIPTION:   Zentrale Framework-Bibliothek (ShellCheck optimized)
# TYPE:          SOURCED MODULE
# AUTHOR:        Stony64
# ------------------------------------------------------------------------------

# --- GUARD (Verhindert mehrfaches Laden) --------------------------------------
[[ -n "${DF_CORE_LOADED:-}" ]] && return 0
readonly DF_CORE_LOADED=1

# --- KONFIGURATION ------------------------------------------------------------
export DF_PROJECT_VERSION="3.4.0"
export DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"

# --- UI KONSTANTEN ------------------------------------------------------------
# Nutze printf für die Definition, um Portabilität zu gewährleisten
DF_C_RED=$(printf '\033[31m')
DF_C_GREEN=$(printf '\033[32m')
DF_C_YELLOW=$(printf '\033[33m')
DF_C_BLUE=$(printf '\033[34m')
DF_C_RESET=$(printf '\033[0m')

DF_SYM_OK='[OK]'
DF_SYM_ERR='[ERR]'
DF_SYM_WARN='[! ]' # Padding für Ausrichtung

# --- 1. LOGGING & UI ----------------------------------------------------------
df_log_info()    { printf '%s--> %s%s\n' "$DF_C_BLUE" "$*" "$DF_C_RESET"; }
df_log_success() { printf '%s%s%s %s\n' "$DF_C_GREEN" "$DF_SYM_OK" "$DF_C_RESET" "$*"; }
df_log_warn()    { printf '%s%s%s %s\n' "$DF_C_YELLOW" "$DF_SYM_WARN" "$DF_C_RESET" "$*"; }
df_log_error()   { printf '%s%s%s %s\n' "$DF_C_RED" "$DF_SYM_ERR" "$DF_C_RESET" "$*" >&2; }

# --- 2. VALIDIERUNG & SYSTEM --------------------------------------------------
df_check_root() {
    if [[ $EUID -ne 0 ]]; then
        df_log_warn "Root-Rechte empfohlen: sudo $(basename "${BASH_SOURCE[1]:-${0}}")"
        return 1
    fi
}

df_is_real_user() {
    local target_user="${1:?User-Parameter fehlt}" uid
    uid=$(getent passwd "$target_user" | cut -d: -f3) || return 1
    [[ "$uid" -eq 0 || "$uid" -ge 1000 ]]
}

df_list_real_users() {
    # Erkennt root und alle menschlichen User, schließt System-Accounts aus
    getent passwd | awk -F: '($3==0 || $3>=1000) && $7!~/nologin|false/ {print $1}' | sort -u
}

df_get_user_home() {
    local target_user="${1:?User-Parameter fehlt}" home
    # Primärer Check über getent (berücksichtigt LDAP/AD/Local)
    home=$(getent passwd "$target_user" | cut -d: -f6)

    if [[ -n "$home" && -d "$home" ]]; then
        printf '%s' "$home"
    else
        # Fallback auf Standardpfad (hilfreich bei frischen Proxmox-Installs)
        if [[ "$target_user" == "root" ]]; then home="/root"; else home="/home/$target_user"; fi

        if [[ -d "$home" ]]; then
            printf '%s' "$home"
        else
            df_log_error "Home nicht gefunden für: $target_user"
            return 1
        fi
    fi
}

# --- 3. DATEI-OPERATIONEN & BACKUP --------------------------------------------
df_backup_create() {
    local user="${1:?User-Parameter fehlt}" home backup_dir timestamp backup_file
    home=$(df_get_user_home "$user") || return 1
    timestamp=$(date +%Y%m%d_%H%M%S)

    # Pfad-Sicherheit: Sichert in Repo-Unterordner
    backup_dir="${DF_REPO_ROOT:?}/backup/${user}_${timestamp}"
    backup_file="${backup_dir}/${user}_dotfiles.tar.gz"

    mkdir -p "$backup_dir"
    df_log_info "Backup-Initialisierung für $user..."

    local files=(.bashrc .profile .bash_profile .vimrc .gitconfig .tmux.conf .ssh/config .bashaliases .bashenv)
    local existing_files=()

    for f in "${files[@]}"; do
        [[ -f "${home}/$f" ]] && existing_files+=("$f")
    done

    if [[ ${#existing_files[@]} -gt 0 ]]; then
        if tar -czf "$backup_file" -C "$home" "${existing_files[@]}" 2>/dev/null; then
            df_log_success "Backup für $user erstellt ($(du -sh "$backup_file" | cut -f1))"
        else
            df_log_error "Fehler beim Packen des Backups."
            return 1
        fi
    else
        df_log_warn "Keine relevanten Dotfiles für $user zum Sichern gefunden."
    fi
}

df_set_owner() {
    local target_path="${1:?Pfad fehlt}"
    local target_user="${2:?User fehlt}"
    local target_group

    [[ ! -e "$target_path" ]] && return 1

    target_group=$(id -gn "$target_user")
    # Sicherheitscheck für chown
    chown -R "${target_user:?}:${target_group:?}" "${target_path:?}"
    df_log_success "Rechte gesetzt: ${target_user}:${target_group} → $(basename "$target_path")"
}

df_create_link() {
    local src="${1:?Source fehlt}"
    local dest="${2:?Destination fehlt}"
    local backup_suffix=".bak_$(date +%Y%m%d_%H%M%S)"

    [[ ! -e "$src" ]] && { df_log_error "Source fehlt: $src"; return 1; }

    # Falls Ziel existiert und kein Link ist -> verschieben
    if [[ -e "$dest" && ! -L "$dest" ]]; then
        mv "$dest" "${dest}${backup_suffix}"
        df_log_warn "Bestand gesichert: $(basename "$dest")$backup_suffix"
    # Falls Ziel ein falscher Link ist -> entfernen
    elif [[ -L "$dest" ]]; then
        if [[ "$(readlink "$dest")" == "$src" ]]; then
            df_log_info "Link bereits korrekt: $(basename "$dest")"
            return 0
        fi
        rm "${dest:?}"
    fi

    ln -snf "$src" "$dest"
    df_log_success "Verlinkt: $(basename "$dest")"
}

df_load_modules() {
    local mod_dir="${DF_REPO_ROOT:?}/lib"
    [[ -d "$mod_dir" ]] || return 0

    shopt -s nullglob
    for mod in "$mod_dir"/*.sh; do
        # Verhindere, dass core.sh sich selbst lädt (falls es in lib/ liegt)
        [[ "$(basename "$mod")" == "core.sh" ]] && continue

        # shellcheck source=/dev/null
        if source "$mod"; then
            df_log_info "Modul geladen: $(basename "$mod")"
        else
            df_log_error "Fehler beim Laden von Modul: $(basename "$mod")"
        fi
    done
    shopt -u nullglob
}
