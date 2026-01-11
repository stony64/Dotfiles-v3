#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         .bashrc
# VERSION:      1.5.2
# DESCRIPTION:  Hauptkonfigurationsdatei mit dynamischem Modul-Loader.
# ------------------------------------------------------------------------------

# --- 1. INTERAKTIV-CHECK ------------------------------------------------------
# Falls nicht interaktiv aufgerufen (z.B. scp/rsync), direkt abbrechen.
[[ $- != *i* ]] && return

# --- 2. PROJEKT-UMGEBUNG ------------------------------------------------------
export DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"
export DF_CORE="${DF_REPO_ROOT}/core.sh"

# --- 3. KERN-BIBLIOTHEK LADEN -------------------------------------------------
if [[ -f "$DF_CORE" ]]; then
    # shellcheck source=/dev/null
    source "$DF_CORE"
else
    printf '\033[31m[ERR]\033[0m Core-Library nicht gefunden: %s\n' "$DF_CORE"
fi

# --- 4. MODULE DYNAMISCH LADEN ------------------------------------------------
# Lädt alle .bash* Dateien aus dem Home-Verzeichnis automatisch.
# .bashenv wird (falls vorhanden) zuerst geladen, um Umgebung zu setzen.

# 4a. Umgebung zuerst
[[ -f "${HOME}/.bashenv" ]] && source "${HOME}/.bashenv"

# 4b. Restliche Module alphabetisch (dynamisch)
for module_path in "${HOME}"/.bash*; do
    [[ -e "$module_path" ]] || continue # Falls kein Match

    filename=$(basename "$module_path")

    case "$filename" in
        # Ausschlussliste: Diese Dateien niemals dynamisch sourcen
        .bashrc|.bash_history|.bash_logout|.bash_profile|.bash_sessions|.bashenv)
            continue
            ;;
        *)
            if [[ -f "$module_path" ]]; then
                # shellcheck source=/dev/null
                source "$module_path"
            fi
            ;;
    esac
done

# --- 5. FRAMEWORK-ALIASE ------------------------------------------------------

# ZWECK: Lädt die gesamte Shell-Umgebung neu.
# shellcheck disable=SC2154
alias reload='source "${HOME}/.bashrc" && df_log_success "Shell-Umgebung v${DF_PROJECT_VERSION} neu geladen."'

# ZWECK: Shortcut für das Dotfiles-Steuerungsskript (SC2139 fix).
if ! command -v dctl >/dev/null 2>&1; then
    alias dctl='sudo "${DF_REPO_ROOT}/dotfilesctl.sh"'
fi

# --- 6. ABSCHLUSS -------------------------------------------------------------
if command -v df_log_info >/dev/null 2>&1; then
    df_log_info "Framework v${DF_PROJECT_VERSION} aktiv (Typ 'tools' für Übersicht)"
fi
