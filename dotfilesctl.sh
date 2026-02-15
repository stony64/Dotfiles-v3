#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:          dotfilesctl.sh
# VERSION:       3.6.3
# DESCRIPTION:   Framework-Controller (ShellCheck-Clean & Logic-optimized)
# AUTHOR:        Stony64
# ------------------------------------------------------------------------------
set -euo pipefail

# --- 1. KONFIGURATION ---------------------------------------------------------
readonly REAL_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly DOTFILES_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR="$HOME/.dotfiles_backups"

# Farben für Log-Ausgaben
export C_RED='\033[0;31m'
export C_GREEN='\033[0;32m'
export C_YELLOW='\033[0;33m'
export C_BLUE='\033[0;34m'
export C_RESET='\033[0m'

log_info()    { printf "${C_BLUE}[INFO]${C_RESET}  %s\n" "$*"; }
log_success() { printf "${C_GREEN}[OK]${C_RESET}    %s\n" "$*"; }
log_warn()    { printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*"; }
log_error()   { printf "${C_RED}[ERR]${C_RESET}   %s\n" "$*" >&2; }

# --- 2. KERNFUNKTIONEN --------------------------------------------------------

backup() {
    local backup_root="${BACKUP_DIR:?}"
    local ts="${TIMESTAMP:?}"
    local current_tmp="$backup_root/$ts"

    log_info "Initialisiere Backup in $backup_root..."
    mkdir -p "$current_tmp"

    local targets=(".bashrc" ".bash_profile" ".gitconfig" ".bashaliases" ".bashenv" ".bashprompt" ".bashfunctions")

    for item in "${targets[@]}"; do
        if [[ -f "$HOME/$item" ]]; then
            cp -L "$HOME/$item" "$current_tmp/$item"
            log_info "Gesichert: $item"
        fi
    done

    if cd "$backup_root" && tar czf "backup-$ts.tar.gz" "$ts"; then
        rm -rf "${current_tmp:?}"
        log_success "Backup erstellt: backup-$ts.tar.gz"
    else
        log_error "Archivierung fehlgeschlagen!"
        return 1
    fi
}

deploy() {
    log_info "Deploying Dotfiles aus $DOTFILES_DIR/home..."
    [[ -d "$DOTFILES_DIR/home" ]] || { log_error "Source 'home/' fehlt!"; exit 1; }

    shopt -s dotglob nullglob
    for src in "$DOTFILES_DIR/home"/*; do
        [[ "$src" == *".bak"* ]] && continue
        local filename=$(basename "$src")
        local dest="$HOME/$filename"

        if [[ -e "$dest" && ! -L "$dest" ]]; then
            log_warn "Datei $filename existiert -> Backup erstellt."
            mv "$dest" "${dest}.bak_${TIMESTAMP}"
        fi

        ln -snf "$src" "$dest"
        printf "  ${C_GREEN}LINK${C_RESET} -> %s\n" "$filename"
    done
    shopt -u dotglob nullglob
}

check_status() {
    log_info "Integritätsprüfung (Repo: $DOTFILES_DIR)"
    local error_count=0

    shopt -s dotglob nullglob
    for src in "$DOTFILES_DIR/home"/*; do
        local f=$(basename "$src")
        local target="$HOME/$f"

        if [[ -L "$target" ]]; then
            local link_target
            link_target=$(readlink "$target")
            if [[ "$link_target" == "$src" ]]; then
                printf "  ${C_GREEN}[OK]${C_RESET}     %s\n" "$f"
            else
                printf "  ${C_RED}[WRONG]${C_RESET}  %s -> %s\n" "$f" "$link_target"
                ((error_count++))
            fi
        elif [[ -e "$target" ]]; then
            printf "  ${C_YELLOW}[FILE]${C_RESET}   %s (blockiert)\n" "$f"
            ((error_count++))
        else
            printf "  ${C_RED}[MISSING]${C_RESET} %s\n" "$f"
            ((error_count++))
        fi
    done
    shopt -u dotglob nullglob

    if [[ $error_count -eq 0 ]]; then
        log_success "Status sauber."
    else
        log_error "$error_count Fehler gefunden."
    fi
}

# --- 3. MAIN EXECUTION --------------------------------------------------------
# --- 3. MAIN EXECUTION --------------------------------------------------------

case "${1:-help}" in
    backup)
        backup
        ;;
    install)
        # FIX SC2310: Funktionen separat aufrufen, damit 'set -e' aktiv bleibt.
        backup
        deploy
        ;;
    reinstall)
        log_warn "Lösche bestehende Links..."
        shopt -s dotglob nullglob
        for src in "$DOTFILES_DIR/home"/*; do
            target="$HOME/$(basename "$src")"
            if [[ -L "$target" ]]; then
                rm "$target"
                printf "  ${C_RED}RM LINK${C_RESET} <- %s\n" "$(basename "$target")"
            fi
        done
        deploy
        ;;
    status)
        check_status
        ;;
    *)
        cat <<EOF
Dotfiles Controller v3.6.4
Nutzung: dctl {backup|install|reinstall|status}
EOF
        ;;
esac
