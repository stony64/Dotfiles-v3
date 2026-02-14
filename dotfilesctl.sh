#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         dotfilesctl.sh
# VERSION:      3.4.7
# DESCRIPTION:  Vollständiges Framework-Tool mit REINSTALL-Funktion.
# AUTHOR:       Stony64
# ------------------------------------------------------------------------------
set -euo pipefail

# --- 1. PFAD-LOGIK & KONFIGURATION --------------------------------------------
readonly REAL_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly DOTFILES_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_BASE="$HOME/.dotfiles-temp-backup-$TIMESTAMP"

# Export für Session-Konsistenz
export DF_REPO_ROOT="$DOTFILES_DIR"

log() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }

# --- 2. KERNFUNKTIONEN --------------------------------------------------------

# Sichert aktuelle Konfigurationen
backup() {
    log "BACKUP: Initialisiere Sicherung in $HOME..."
    mkdir -p "$BACKUP_BASE"
    local targets=(
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.gitconfig"
        "$HOME/.tmux.conf" "$HOME/.vimrc" "$HOME/.bashaliases"
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

# Verlinkt Dateien dynamisch
deploy() {
    log "DEPLOY: Verlinke Home-Dateien aus $DOTFILES_DIR/home -> $HOME"

    shopt -s dotglob nullglob
    for src in "$DOTFILES_DIR/home"/*; do
        [[ -d "$src" ]] && continue
        local filename=$(basename "$src")
        local dest="$HOME/$filename"

        # Backup bei regulärer Datei (kein Link)
        if [[ -f "$dest" && ! -L "$dest" ]]; then
            log "\e[33mWARN\e[0m: $filename ist eine Datei. Backup erstellt."
            mv "$dest" "${dest}.bak_${TIMESTAMP}"
        fi

        ln -snf "$src" "$dest"
        log "\e[32mLINK\e[0m: $filename verknüpft."
    done
    shopt -u dotglob nullglob
}

# REINSTALL: Löscht bestehende Links und installiert neu
reinstall() {
    echo -e "\e[31m!!! ACHTUNG !!!\e[0m"
    echo "Dies löscht alle bestehenden Dotfile-Symlinks im Home-Verzeichnis und setzt sie neu."
    read -p "Fortfahren? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Abbruch durch Benutzer."
        return 1
    fi

    log "REINSTALL: Lösche alte Symlinks..."
    shopt -s dotglob nullglob
    for src in "$DOTFILES_DIR/home"/*; do
        [[ -d "$src" ]] && continue
        local filename=$(basename "$src")
        local dest="$HOME/$filename"

        if [[ -L "$dest" ]]; then
            rm "$dest"
            log "REMOVED: Link $filename gelöscht."
        fi
    done
    shopt -u dotglob nullglob

    log "REINSTALL: Starte Neuinstallation..."
    deploy
}

# Statusprüfung
check_status() {
    log "STATUS: Prüfung gegen Repository: $DOTFILES_DIR"
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
case "${1:-help}" in
    backup)            backup ;;
    install|deploy)    deploy ;;
    reinstall)         reinstall ;;
    status)            check_status ;;
    *)
        cat <<EOF
Nutzung: $SCRIPT_NAME {backup|install|reinstall|status}

Befehle:
  backup     Sichert Dateien in ein tar.gz Archiv.
  install    Verlinkt alle Dateien aus ./home/ nach $HOME.
  reinstall  Löscht bestehende Symlinks und installiert sie neu.
  status     Prüft die Integrität der Links.

Version: 3.4.7 (Pfad: $DOTFILES_DIR)
EOF
        exit 0
        ;;
esac
