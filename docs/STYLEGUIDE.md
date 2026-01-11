# Dotfiles Framework Style-Guide (v1.4.2)

## 1. Dateistruktur & Header

Jede Bash-Datei folgt diesem Aufbau (whitespace-sensitiv):

```bash
#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        <Pfad/Name relativ zu DF_REPO_ROOT>
# VERSION:     <X.Y.Z>
# DESCRIPTION: <Kurze Beschreibung auf Deutsch>
# TYPE:        <EXECUTABLE | SOURCED MODULE>
# ------------------------------------------------------------------------------

```

### Idempotency Guard (für Sourced Modules)

Bibliotheken müssen ein mehrfaches Laden verhindern:

```bash
[[ -n "${DF_CORE_LOADED:-}" ]] && return 0
readonly DF_CORE_LOADED=1

```

---

## 2. Dokumentation & Modul-Struktur

### Funktions-Header (Pflicht)

Jede Funktion muss durch einen standardisierten Header dokumentiert sein.

```bash
# ZWECK: Kurze, präzise Beschreibung der Aufgabe.
# PARAM: $1 (Typ) - Name/Bedeutung.
# RETURN: 0 bei Erfolg, >0 bei Fehler (Statuscode).
function_name() {
    local param="$1"
    # ...
}

```

### Logische Gruppierung

Funktionen innerhalb eines Moduls sind mit Block-Überschriften zu gruppieren:

```bash
# --- 1. NETZWERK & IP ---------------------------------------------------------

```

---

## 3. Namenskonventionen & Präfixe

- **Präfix `df_**`: Exklusiv reserviert für Framework-Kernfunktionen (Logik, Install, Backup, Logging).
- **Neutral (kein Präfix)**: Für allgemeine Benutzer-Werkzeuge und Helfer (z. B. `extract`, `hg`, `ff`), um die tägliche Nutzung im Terminal zu erleichtern.
- **Globale Variablen**: `DF_UPPER_CASE` (z. B. `DF_REPO_ROOT`).
- **Lokale Variablen**: `lower_case` via `local`, gruppiert am Funktionsanfang.

---

## 4. Logging & UX (P2)

Es ist zwingend die framework-eigene Logging-Suite zu verwenden:

- `df_log_info`: Fortschritt/Informationen.
- `df_log_success`: Erfolgsmeldungen.
- `df_log_error`: Fehlermeldungen (Ausgabe erfolgt auf **stderr**).

---

## 5. Security & Idempotenz (P0/P1)

- **Quoting:** Jede Expansion wird gequotet `"$var"`.
- **User-Daten:** `getent passwd` ist das Hard-Requirement für Linux-Systeme.
- **Ownership:** Bei Root-Ausführung muss bei Verzeichniserstellung (`mkdir`) der Owner via `chown` auf den Ziel-User korrigiert werden.
- **Backups:** Nur für echte Dateien (`.bak_<timestamp>`). Bestehende Symlinks werden ohne Backup ersetzt.

---

## 6. Statische Analyse

- Alle Dateien müssen ShellCheck bestehen (0 Warnungen).
- Begründete Ausnahmen werden lokal annotiert: `# shellcheck disable=SCxxxx`.
