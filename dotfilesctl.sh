#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         dotfilesctl.sh
# VERSION:      3.4.5
# DESCRIPTION:  Vollständiger CLI-Entrypoint (Dynamisches Home + System + Backup)
# AUTHOR:       Stony64
# ------------------------------------------------------------------------------
set -euo pipefail

# --- 1. KONFIGURATION --------------------------------------------
readonly REAL_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly DOTFILES_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_BASE="$HOME/.dotfiles-temp-backup-$TIMESTAMP"

log() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }

# --- 2. KERNFUNKTIONEN --------------------------------------------------------

# Sichert aktuelle Konfigurationen als komprimiertes Archiv
backup() {
    log "BACKUP: Initialisiere Sicherung in $HOME..."
    mkdir -p "$BACKUP_BASE"

    # Liste der Dateien, die gesichert werden sollen (Home + System)
    local targets=(
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.gitconfig"
        "$HOME/.tmux.conf" "$HOME/.vimrc" "$HOME/.bashaliases"
        "/etc/systemd/user/pipewire.service.d/99-proxmox.conf"
    )

    for item in "${targets[@]}"; do
        if [[ -e "$item" ]]; then
            local dest="$BACKUP_BASE${item}"
            mkdir -p "$(dirname "$dest")"
            cp -a "$item" "$dest"
            log "BACKUP: $item gesichert."
        fi
    done

    tar czf "$HOME/dotfiles-backup-$TIMESTAMP.tar.gz" -C "$BACKUP_BASE" . 2>/dev/null
    rm -rf "$BACKUP_BASE"
    log "BACKUP: Archiv erstellt: ~/dotfiles-backup-$TIMESTAMP.tar.gz"
}

# Rollt Symlinks dynamisch aus und setzt System-Settings
deploy() {
    log "DEPLOY: Verlinke Dateien aus $DOTFILES_DIR/home -> $HOME"

    shopt -s dotglob nullglob
    for src in "$DOTFILES_DIR/home"/*; do
        # Nur Dateien verarbeiten, Verzeichnisse überspringen (außer 'config' falls nötig)
        [[ -d "$src" ]] && continue

        local filename=$(basename "$src")
        local dest="$HOME/$filename"

        if [[ -f "$dest" && ! -L "$dest" ]]; then
            log "\e[33mWARN\e[0m: $filename ist eine Datei. Erstelle Backup..."
            mv "$dest" "${dest}.bak_${TIMESTAMP}"
        fi

        ln -snf "$src" "$dest"
        log "\e[32mLINK\e[0m: $filename verknüpft."
    done
    shopt -u dotglob nullglob

    # --- SYSTEM EBENE (Proxmox/ETC) ---
    if [[ -d "$DOTFILES_DIR/etc" ]]; then
        log "SYS: Konfiguriere System-Komponenten..."
        sudo mkdir -p "/etc/systemd/user/pipewire.service.d/"
        if [[ -f "$DOTFILES_DIR/etc/proxmox.conf" ]]; then
            sudo ln -sf "$DOTFILES_DIR/etc/proxmox.conf" "/etc/systemd/user/pipewire.service.d/99-proxmox.conf"
            log "SYS: Pipewire Proxmox-Fix verlinkt."
        fi

        # ZFS Optimierung
        if command -v zpool >/dev/null 2>&1; then
            if sudo zpool list proxmox >/dev/null 2>&1; then
                sudo zpool set cachefile=/etc/zfs/zpool.cache proxmox
                log "SYS: ZFS Cachefile für 'proxmox' gesetzt."
            fi
        fi
    fi
    log "DEPLOY: Abgeschlossen."
}

# Überprüft den Status aller Dateien im Repo
check_status() {
    log "STATUS: Integritätsprüfung (Basis: Repository-Inhalt)"
    shopt -s dotglob nullglob
    for src in "$DOTFILES_DIR/home"/*; do
        [[ -d "$src" ]] && continue
        local f=$(basename "$src")
        local target="$HOME/$f"

        if [[ -L "$target" ]]; then
            [[ "$(readlink "$target")" == "$src" ]] && echo -e "\e[32m[OK]\e[0m $f" || echo -e "\e[31m[WRONG]\e[0m $f"
        elif [[ -e "$target" ]]; then
            echo -e "\e[31m[FILE]\e[0m $f (blockiert)"
        else
            echo -e "\e[33m[MISSING]\e[0m $f"
        fi
    done
    shopt -u dotglob nullglob
}

# --- 3. MAIN (EXECUTION) ------------------------------------------------------
main() {
    case "${1:-help}" in
        backup)         backup ;;
        install|deploy) deploy ;;
        status)         check_status ;;
        *)
            cat <<EOF
Nutzung: $SCRIPT_NAME {backup|install|status}

Befehle:
  backup   Sichert Home- & System-Files in ein tar.gz Archiv.
  install  Verlinkt dynamisch alle Dateien aus ./home/ nach $HOME.
  status   Prüft, ob die Links im Home korrekt auf das Repo zeigen.

Version: 3.4.5 (Repo: $DOTFILES_DIR)
EOF
            exit 0
            ;;
    esac
}

main "$@"
