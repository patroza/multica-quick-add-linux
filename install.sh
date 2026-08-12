#!/usr/bin/env bash
# Install Multica Quick Add into the local Walker / Elephant setup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
ELEPHANT_MENUS="${HOME}/.config/elephant/menus"
WALKER_CONFIG="${HOME}/.config/walker/config.toml"

mkdir -p "$BIN_DIR" "$ELEPHANT_MENUS"

ln -sfn "$ROOT/bin/multica-quick-add" "$BIN_DIR/multica-quick-add"
chmod +x "$ROOT/bin/multica-quick-add"

ln -sfn "$ROOT/elephant/menus/multicaquickadd.lua" "$ELEPHANT_MENUS/multicaquickadd.lua"

# Walker: ensure the menu provider is listed (idempotent)
if [[ -f "$WALKER_CONFIG" ]]; then
  if ! grep -q 'menus:multicaquickadd' "$WALKER_CONFIG"; then
    # Insert into installed_providers array if present
    if grep -q 'installed_providers' "$WALKER_CONFIG"; then
      tmp="$(mktemp)"
      awk '
        BEGIN { done=0 }
        /installed_providers/ { inarr=1 }
        inarr && /^\s*\]/ && !done {
          print "  \"menus:multicaquickadd\","
          done=1
        }
        { print }
      ' "$WALKER_CONFIG" >"$tmp"
      mv "$tmp" "$WALKER_CONFIG"
      echo "Added menus:multicaquickadd to $WALKER_CONFIG installed_providers"
    fi
  fi

  if ! grep -q 'provider = "menus:multicaquickadd"' "$WALKER_CONFIG"; then
    cat >>"$WALKER_CONFIG" <<'EOF'

[[providers.prefixes]]
prefix = "mqa"
provider = "menus:multicaquickadd"
EOF
    echo "Added Walker prefix 'mqa' for Multica Quick Add"
  fi
else
  echo "No $WALKER_CONFIG found — skip walker wiring"
fi

if command -v omarchy-restart-walker >/dev/null 2>&1; then
  omarchy-restart-walker || true
elif command -v systemctl >/dev/null 2>&1; then
  systemctl --user try-restart elephant.service 2>/dev/null || true
fi

cat <<EOF

Installed:
  $BIN_DIR/multica-quick-add
  $ELEPHANT_MENUS/multicaquickadd.lua

Usage:
  multica-quick-add              # prompt with last agent
  multica-quick-add --pick       # reselect workspace/project/agent
  multica-quick-add --configure  # save defaults only
  walker -m menus:multicaquickadd
  Type prefix "mqa" in Walker

Suggested niri bind (Ctrl+Shift+M — Multica):
  Ctrl+Shift+M { spawn-sh "multica-quick-add"; }

  Or exclusive menu:
  Ctrl+Shift+M { spawn-sh "omarchy-launch-walker -m menus:multicaquickadd"; }

Requires Multica CLI login:
  multica setup
EOF
