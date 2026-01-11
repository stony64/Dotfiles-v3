#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         dotfilesctl.sh
# VERSION:      3.1.2
# DESCRIPTION:  Hauptsteuerung des Dotfiles-Frameworks (CLI Entrypoint).
# TYPE:         EXECUTABLE
# ------------------------------------------------------------------------------

set -euo pipefail

# --- BOOTSTRAP ----------------------------------------------------------------
export DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"

# SC2154 Fix: ShellCheck über externe Variablen informieren
# Diese Variablen werden in core.sh definiert.
# shellcheck disable=SC2034
DF_PROJECT_VERSION="${DF_PROJECT_VERSION:-}"

# Sicherstellen, dass der Kern geladen wird
if [[ -f "${DF_REPO_ROOT}/core.sh" ]]; then
    # shellcheck source=core.sh
    source "${DF_REPO_ROOT}/core.sh"
else
    printf '[ERR] Framework-Kern nicht gefunden unter %s\n' "${DF_REPO_ROOT}/core.sh" >&2
    exit 1
fi

df_load_modules

# --- 1. KERN-LOGIK ------------------------------------------------------------

# ZWECK: Installiert Dotfiles für einen spezifischen User inklusive Backup-Check.
# PARAM: $1 (String) - Username.
# RETURN: 0 bei Erfolg, >0 bei Fehlern.
df_install_user() {
    local user="$1"
    local home_dir src_dir item base_name

    df_is_real_user "$user" || { df_log_error "Ungültiger oder System-User: $user"; return 1; }

    home_dir=$(df_get_user_home "$user")
    src_dir="${DF_REPO_ROOT}/home"

    df_log_info "Starte Installation für User: $user ($home_dir)"

    # Backup-Integration (P1)
    if declare -f df_backup_create > /dev/null; then
        df_backup_create "$user" || { df_log_error "Backup fehlgeschlagen! Abbruch."; return 1; }
    fi

    # Deployment-Schleife (P1/P3)
    while read -r item; do
        base_name=$(basename "$item")
        df_create_link "$item" "${home_dir}/${base_name}"
        df_set_owner "${home_dir}/${base_name}" "$user"
    done < <(find "$src_dir" -maxdepth 1 -mindepth 1)

    df_log_success "Dotfiles für $user erfolgreich installiert."
}

# ZWECK: Prüft den Link-Status für einen User ohne ls-parsing (P2).
# PARAM: $1 (String) - Username.
# RETURN: 0
df_status_user() {
    local user="$1"
    local home_dir item target
    local found=0

    home_dir=$(df_get_user_home "$user")
    df_log_info "Status der Framework-Links für $user:"

    # SC2010 Fix: Nutzt Globbing statt ls | grep
    for item in "${home_dir}"/.*; do
        [[ -L "$item" ]] || continue

        target=$(readlink -f "$item")
        if [[ "$target" == "${DF_REPO_ROOT}"* ]]; then
            printf '  [LINK] %s -> %s\n' "$(basename "$item")" "$target"
            found=1
        fi
    done

    [[ "$found" -eq 0 ]] && echo "  Keine aktiven Framework-Links gefunden."
    return 0
}

# --- 2. SYSTEM-INTEGRATION ----------------------------------------------------

# ZWECK: Registriert dctl systemweit unter /usr/local/bin (Idempotent).
# RETURN: 0
df_register_dctl() {
    local link_path="/usr/local/bin/dctl"
    local script_path="${DF_REPO_ROOT}/dotfilesctl.sh"

    [[ $EUID -ne 0 ]] && return 0

    if [[ "$(readlink -f "$link_path" 2>/dev/null || true)" != "$script_path" ]]; then
        df_log_info "Registriere 'dctl' systemweit..."
        ln -sf -- "$script_path" "$link_path"
        chmod +x -- "$script_path"
    fi
}

# --- MAIN ---------------------------------------------------------------------

CMD="${1:-help}"
TARGET="${2:-$USER}"

df_register_dctl

case "$CMD" in
    install)
        if [[ "$TARGET" == "--all" ]]; then
            for u in $(df_list_real_users); do
                df_install_user "$u"
            done
        else
            df_install_user "$TARGET"
        fi
        ;;
    status)
        df_status_user "$TARGET"
        ;;
    version)
        # Jetzt sicher für ShellCheck
        printf 'Dotfiles Framework %s\n' "$DF_PROJECT_VERSION"
        ;;
    help|*)
        printf 'Nutzung: dctl {install|status|version} [user|--all]\n'
        ;;
esac
