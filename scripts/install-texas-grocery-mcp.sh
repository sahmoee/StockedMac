#!/bin/zsh
set -euo pipefail

expected_uuid="2FA10041-73EB-43A7-A151-CF3DFDC2A3F3"
volume="/Volumes/Macintosh SSD"
runtime="$volume/MacStorage/Developer/MCP/texas-grocery-mcp"
browsers="$volume/MacStorage/Caches/Playwright"

actual_uuid="$(diskutil info "$volume" | awk -F: '/Volume UUID/ {gsub(/[[:space:]]/, "", $2); print $2}')"
if [[ "$actual_uuid" != "$expected_uuid" ]]; then
  print -u2 "Refusing install: expected SSD UUID $expected_uuid, found ${actual_uuid:-none}."
  exit 1
fi

brew_bin="/opt/homebrew/bin/brew"
[[ -x "$brew_bin" ]] || { print -u2 "Homebrew is required at $brew_bin."; exit 1; }
"$brew_bin" list python@3.13 >/dev/null 2>&1 || "$brew_bin" install python@3.13

mkdir -p "$runtime/state" "$browsers"
/opt/homebrew/bin/python3.13 -m venv "$runtime/venv"
"$runtime/venv/bin/python" -m pip install --upgrade pip
"$runtime/venv/bin/pip" install --upgrade \
  'texas-grocery-mcp[browser] @ git+https://github.com/mgwalkerjr95/texas-grocery-mcp.git@main'
PLAYWRIGHT_BROWSERS_PATH="$browsers" "$runtime/venv/bin/playwright" install chromium
"$runtime/venv/bin/python" -c 'import texas_grocery_mcp; print("Texas Grocery MCP ready")'

print "Runtime: $runtime"
print "Browser cache: $browsers"
print "Codex config must point texas_grocery at: $runtime/venv/bin/texas-grocery-mcp"
