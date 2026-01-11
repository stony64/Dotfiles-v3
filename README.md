# 🛠 Dotfiles Framework v3.1.1

Ein hochgradig modularer, Multi-User-fähiger Dotfiles-Manager zur zentralen Verwaltung und sicheren Verteilung von Systemkonfigurationen unter `/opt/dotfiles`.

## 🌟 Hauptmerkmale

* **Modulare Architektur:** Funktionale Logik ist konsequent in `lib/` ausgelagert.
* **Sicherheits-Backup:** Automatisierte `.tar.gz`-Snapshots vor jeder Änderung (P1 - Idempotenz).
* **Multi-User Support:** Zentrale Installation, individuelle Verteilung per User oder `--all`.
* **Code-Qualität:** Volle Integration von ShellCheck und Markdown-Linting.

## 📁 Projektstruktur

```text
/opt/dotfiles/
├── core.sh                  # Framework-Kern (Versionen & UI-Definitionen)
├── dotfilesctl.sh           # Hauptsteuerung (CLI-Entrypoint 'dctl')
├── lib/                     # Modul-Bibliothek (Backup, Tools, etc.)
├── home/                    # Repository der Konfigurationsdateien
│   ├── .bash* # Shell-Konfigurationen (.bashrc, .bashaliases, etc.)
│   └── config/              # App-Configs (XDG-Struktur für mc, micro, etc.)
├── docs/
│   └── STYLEGUIDE.md        # Zentraler Styleguide für das Framework
├── .shellcheckrc            # Statische Code-Analyse Konfiguration (Bash)
├── .markdown*.jsonc         # Markdown-Linting Konfigurationen (CLI-2)
└── .editorconfig            # Editor-Übergreifende Formatierungsregeln

```

## 🚀 Installation & Nutzung

### 1. Framework bereitstellen

Zuerst wird das Repository an den Standard-Ort geklont:

```bash
sudo git clone https://github.com/Stony64/dotfiles-v3.git /opt/dotfiles

```

### 2. Erstinstallation & Registrierung

Beim ersten Lauf wird das Framework systemweit registriert. Dies erzeugt automatisch einen Symlink unter `/usr/local/bin/dctl`, damit das Tool ab sofort als Kommando `dctl` verfügbar ist.

**Hinweis:** Der erste Aufruf sollte mit `sudo` erfolgen, um das System-Kommando zu registrieren und die Dotfiles für den aktuellen User zu installieren.

```bash
sudo /opt/dotfiles/dotfilesctl.sh install "$USER"

```

### 3. Tägliche Nutzung

Nach der Erstinstallation kannst du das Framework einfach über `dctl` steuern:

```bash
dctl status "$USER"
dctl install "$USER"

```

> **Sicherheit:** Vor jeder Installation wird automatisch ein Backup erstellt. Sollte die Backup-Erstellung fehlschlagen, bricht das Framework den Vorgang sofort ab.

## 🛠 Standards

* **Indentation:** 4 Spaces (Bash, JSON, YAML) via `.editorconfig`.
* **Shell:** Bash 4.0+ Fokus.
* **Linter:** ShellCheck v0.9.0+ konform.
* **Lizenz:** MIT

---

*Dokumentation aktualisiert für Framework Version 3.1.1.*

---
