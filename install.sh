#!/usr/bin/env bash
# install.sh — instala Claude-StatusBar en Windows (Git Bash), macOS y Linux

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/custom_bar.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# ── Detectar entorno ─────────────────────────────────────────────────────────
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;;
    *) WINDOWS=0 ;;
esac

echo "Instalando Claude-StatusBar..."
echo ""

# ── Copiar el script ─────────────────────────────────────────────────────────
mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_DIR/custom_bar.sh" "$DEST"
chmod +x "$DEST"
echo "✓ Script instalado en: $DEST"

# ── Ruta del comando para settings.json ─────────────────────────────────────
# Claude Code no expande '~'; necesita la ruta absoluta.
# En Windows (Git Bash), /c/Users/... debe convertirse a C:/Users/...
if [ "$WINDOWS" = "1" ]; then
    WIN_PATH=$(cygpath -m "$DEST")
    CMD="bash '${WIN_PATH}'"
else
    CMD="$DEST"
fi

# ── Actualizar settings.json ─────────────────────────────────────────────────
_python=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

if [ -z "$_python" ]; then
    echo ""
    echo "⚠  Python no encontrado. Añade esto manualmente a ~/.claude/settings.json:"
    echo "   \"statusLine\": { \"type\": \"command\", \"command\": \"$CMD\" }"
    exit 0
fi

"$_python" - "$SETTINGS" "$CMD" <<'PYEOF'
import json, sys, os

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

settings_file = sys.argv[1]
command       = sys.argv[2]

if os.path.exists(settings_file):
    with open(settings_file, encoding='utf-8') as f:
        try:
            cfg = json.load(f)
        except json.JSONDecodeError:
            cfg = {}
else:
    cfg = {}

cfg['statusLine'] = {'type': 'command', 'command': command}

os.makedirs(os.path.dirname(os.path.abspath(settings_file)), exist_ok=True)
with open(settings_file, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"✓ settings.json actualizado: {settings_file}")
PYEOF

echo ""
echo "Instalación completada. Reinicia Claude Code para activar la barra de estado."
