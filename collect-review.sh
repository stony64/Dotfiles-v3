#!/usr/bin/env bash
# ==============================================================================
# collect-review.sh – dotfiles Aggregator v3.6.0
# ==============================================================================
# Zweck: Optimierter Dump für KI-gestützte Rekonstruktion mit expliziten Metadaten.
# Nutzung: bash scripts/collect-review.sh [Target-Dir] [--all]
# Version: 3.6.0 | Last Update: 2026-01-25
# ==============================================================================

# --- 1. KONFIGURATION & PARAMETER ---
SCRIPT_VERSION="3.6.0"
TARGET_DIR="${1:-$(pwd)}"
PROJECT_NAME="dotfiles"
ALL_FILES=false

# Parameter-Parsing
for arg in "$@"; do
  [[ "$arg" == "--all" ]] && ALL_FILES=true
done

# Verzeichnis validieren (Support für Windows-Paths via Git Bash)
if [[ ! -d "$TARGET_DIR" ]]; then
  echo -e "\033[0;31mFehler: Verzeichnis $TARGET_DIR nicht gefunden.\033[0m"
  exit 1
fi

# Export-Ordner erstellen (im Root des Repositories)
OUTPUT_DIR="${TARGET_DIR}/_exports"
mkdir -p "$OUTPUT_DIR"

# Dateiname generieren
SCOPE="review"
[[ "$ALL_FILES" == true ]] && SCOPE="full-dump"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="${PROJECT_NAME}_${SCOPE}_${TIMESTAMP}.txt"
OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME}"

# --- 2. AUSSCHLUSS-LOGIK ---
# Verzeichnisse und Dateitypen, die ignoriert werden
# Wir schließen binäre Assets und interne Git-Strukturen aus
EXCLUDE_REGEX='/(\.git|_exports|node_modules|test_sandbox|bin|obj|\.vs)/|(\.bak$|\.png$|\.jpg$|\.pdf$|\.ico$|\.zip$|LICENSE$)'

# --- 3. EXPORT ENGINE ---
{
  echo "--- ${PROJECT_NAME^^} DUMP PROTOCOL V$SCRIPT_VERSION ---"
  echo "METADATA | SOURCE: $TARGET_DIR | TIMESTAMP: $(date)"
  echo "---------------------------------------------------------------------------"

  # Find-Kette mit Null-Termination für Leerzeichen-Sicherheit
  find "$TARGET_DIR" -type f -print0 | sort -z | while IFS= read -r -d '' file; do

    # Relativen Pfad berechnen
    rel_path="${file#"${TARGET_DIR}/"}"

    # Ausschluss-Prüfung
    if [[ "/$rel_path" =~ $EXCLUDE_REGEX ]]; then
      continue
    fi

    # Metadaten extrahieren
    extension="${file##*.}"
    # Spezial-Handling für dotfiles ohne Endung
    [[ "$rel_path" == *".bash"* ]] && extension="bash"
    [[ "$rel_path" == *".gitattributes"* ]] && extension="gitattributes"
    [[ "$rel_path" == *".gitignore"* ]] && extension="gitignore"

    line_count=$(wc -l < "$file" 2>/dev/null || echo "0")

    # Strukturierter Block-Header
    echo "[FILE_START] path=\"$rel_path\" type=\".$extension\" lines=$line_count"
    echo "--- CONTENT START ---"

    # Dateiinhalt einfügen
    cat "$file"

    # Sicherstellen, dass der Block sauber abschließt
    echo -e "\n--- CONTENT END ---"
    echo "[FILE_END] path=\"$rel_path\""
    echo "---------------------------------------------------------------------------"
  done

  echo "--- END OF DUMP ---"
} > "$OUTPUT_FILE"

# --- 4. OUTPUT & INTEGRATION ---
echo -e "\033[0;32mExport erfolgreich: $FILENAME\033[0m"
echo -e "\033[0;36mFormat: v$SCRIPT_VERSION (Strukturiertes Framework-Tag-System)\033[0m"

# Clipboard-Handling (Hybrid: Git Bash / WSL / Linux)
if command -v clip.exe >/dev/null 2>&1; then
  cat "$OUTPUT_FILE" | clip.exe
  echo "Inhalt wurde in die Windows-Zwischenablage kopiert."
elif command -v xclip >/dev/null 2>&1; then
  cat "$OUTPUT_FILE" | xclip -selection clipboard
  echo "Inhalt wurde in die X11-Zwischenablage kopiert."
fi

# Explorer-Integration (Nur Windows/Git-Bash/WSL)
if command -v explorer.exe >/dev/null 2>&1; then
  # cygpath stellt sicher, dass der Pfad für Windows verständlich ist
  explorer.exe "$(cygpath -w "$OUTPUT_DIR" 2>/dev/null || echo "$OUTPUT_DIR")"
fi
