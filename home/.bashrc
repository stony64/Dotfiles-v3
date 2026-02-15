#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:          .bashrc
# VERSION:       1.7.0
# DESCRIPTION:   Hauptkonfigurationsdatei mit dynamischem Modul-Loader.
# AUTHOR:        Stony64
# ------------------------------------------------------------------------------
# shellcheck shell=bash

# --- 1. INTERAKTIV-CHECK ------------------------------------------------------
[[ $- != *i* ]] && return

# --- 2. PROJEKT-UMGEBUNG ------------------------------------------------------
export DF_REPO_ROOT="/opt/dotfiles"
export DF_CORE="${DF_REPO_ROOT}/core.sh"

# --- 3. KERN-BIBLIOTHEK LADEN -------------------------------------------------
if [[ -f "$DF_CORE" ]]; then
    # shellcheck source=/dev/null
    source "$DF_CORE"
else
    printf '\033[31m[ERR]\033[0m Core-Library nicht gefunden: %s\n' "$DF_CORE" >&2
fi

# Fallback Version
: "${DF_PROJECT_VERSION:=3.5.0}"

# --- 4. MODULE DYNAMISCH LADEN ------------------------------------------------
# .bashenv immer zuerst, da sie Variablen für andere Module bereitstellt
[[ -r "${HOME}/.bashenv" ]] && source "${HOME}/.bashenv"

for module_path in "${HOME}"/.bash*; do
    # Filename extrahieren ohne basename-Prozess
    filename="${module_path##*/}"

    # Blacklist: Diese Dateien niemals dynamisch laden
    case "$filename" in
        .bashrc|.bash_history|.bash_logout|.bash_profile|.bash_completion) continue ;;
        *.bak|*~|*.swp) continue ;; # Ignoriere Backups und Editor-Temps
    esac

    [[ -r "$module_path" ]] || continue

    # Logge Laden (nur wenn interaktiv und Funktion vorhanden)
    if command -v df_log_info >/dev/null 2>&1; then
        df_log_info "Lade Modul: $filename"
    fi

    # shellcheck source=/dev/null
    source "$module_path"
done

# --- 5. FRAMEWORK + SYSTEM ALIASE ---------------------------------------------

# Komfort-Funktion zum Neuladen
reload() {
    if source "${HOME}/.bashrc"; then
        if command -v df_log_success >/dev/null 2>&1; then
            df_log_success "Shell v${DF_PROJECT_VERSION} neu geladen."
        else
            echo "[OK] Shell neu geladen."
        fi
    fi
}

# Dotfiles Control Alias (Fallback wenn kein Binär-Link existiert)
if ! command -v dctl >/dev/null 2>&1; then
    alias dctl='sudo "${DF_REPO_ROOT}/dotfilesctl.sh"'
fi

# Framework Tools Übersicht
tools() {
    local blue='\033[34m'
    local reset='\033[0m'
    printf "\n%bFramework Tools v%s:%b\n" "${blue}" "${DF_PROJECT_VERSION}" "${reset}"
    printf "  reload    → Shell-Konfiguration frisch einlesen\n"
    printf "  dctl      → Dotfiles Management Utility\n"
    printf "  dutop     → Top 10 Platzfresser (aktuell)\n"
    printf "  dutopall  → Top 10 Platzfresser (rekursiv)\n"
    printf "  path      → Formatierten \$PATH anzeigen\n"
    printf "  myip      → Lokale & Öffentliche IP prüfen\n\n"

    if command -v dctl >/dev/null 2>&1; then
        dctl status "$USER"
    fi
}

# --- 6. PROMPT FALLBACK -------------------------------------------------------
# Wenn .bashprompt nicht geladen wurde (PS1 ist noch Standard), setzen wir Basis.
if [[ "$PS1" == "\\s-\\v\\\$ " || -z "${PS1:-}" ]]; then
    if [[ $EUID -eq 0 ]]; then
        PS1='\[\033[31m\]\h:\w\$\[\033[0m\] '
    else
        PS1='\[\033[32m\]\u@\h:\w\$\[\033[0m\] '
    fi
fi

# --- 7. ABSCHLUSS -------------------------------------------------------------
# Begrüßung beim Login
if command -v df_log_info >/dev/null 2>&1; then
    df_log_info "Framework v${DF_PROJECT_VERSION} aktiv. Tippe 'tools' für Hilfe."
fi
