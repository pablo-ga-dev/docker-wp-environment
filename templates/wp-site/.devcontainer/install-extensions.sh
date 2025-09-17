#!/usr/bin/env bash
set -euo pipefail

EXT_DIR="/var/www/.vscode-server/extensions"
DATA_DIR="/var/www/.vscode-server/data"
MARKER_DIR="$DATA_DIR/Machine"
MARKER_FILE="$MARKER_DIR/.extensions_installed"

# Ensure dirs exist
mkdir -p "$EXT_DIR"
mkdir -p "$MARKER_DIR"

if [ -f "$MARKER_FILE" ]; then
  echo "Extensions already installed (marker present). Skipping. Remove $MARKER_FILE to force reinstall."
  exit 0
fi

# Find code-server binary reliably (search any version folder)
CODE_SERVER_BIN=""
for p in /var/www/.vscode-server/bin/*/bin/code-server; do
  if [ -x "$p" ]; then
    CODE_SERVER_BIN="$p"
    break
  fi
done

if [ -z "$CODE_SERVER_BIN" ]; then
  echo "No code-server binary found under /var/www/.vscode-server/bin/*/bin/code-server"
  exit 0
fi

echo "Using code-server: $CODE_SERVER_BIN"

# Desired extensions (keep in sync with devcontainer.json)
EXTS=(
  dbaeumer.vscode-eslint
  eamodio.gitlens
  bmewburn.vscode-intelephense-client
  xdebug.php-debug
  esbenp.prettier-vscode
  yzhang.markdown-all-in-one
  Gruntfuggly.todo-tree
  DotJoshJohnson.xml
  EditorConfig.editorconfig
  redhat.vscode-yaml
  streetsidesoftware.code-spell-checker
  mikestead.dotenv
  bradlc.vscode-tailwindcss
  stylelint.vscode-stylelint
  ms-azuretools.vscode-docker
  johnbillion.vscode-wordpress-hooks
)
)

FAILED=0
for ext in "${EXTS[@]}"; do
  echo "-> Installing $ext ..."
  if "$CODE_SERVER_BIN" --extensions-dir "$EXT_DIR" --install-extension "$ext"; then
    echo "   OK: $ext"
  else
    echo "   ERROR installing $ext"
    FAILED=1
  fi
done

echo "Installation finished. Listing $EXT_DIR:"
ls -la "$EXT_DIR" || true

# Write extensions.json so VS Code sees the list (useful for some workflows)
EXTS_JSON_FILE="$EXT_DIR/extensions.json"
printf '{"recommendations":[' > "$EXTS_JSON_FILE"
first=1
for ext in "${EXTS[@]}"; do
  if [ $first -eq 1 ]; then
    printf '"%s"' "$ext" >> "$EXTS_JSON_FILE"
    first=0
  else
    printf ',"%s"' "$ext" >> "$EXTS_JSON_FILE"
  fi
done
printf ']}' >> "$EXTS_JSON_FILE"

# Ensure ownership to www-data (safe even if running as www-data)
if id -u www-data >/dev/null 2>&1; then
  chown -R www-data:www-data /var/www/.vscode-server || true
fi

# Create marker so we don't run again
date --iso-8601=seconds > "$MARKER_FILE" || touch "$MARKER_FILE"

if [ $FAILED -ne 0 ]; then
  echo "Some extensions failed to install. See output above. Remove $MARKER_FILE and re-run to retry."
  exit 2
fi

echo "All extensions installed successfully. Marker written to $MARKER_FILE"
