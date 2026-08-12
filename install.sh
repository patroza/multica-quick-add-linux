#!/usr/bin/env bash
# Install Multica Quick Add into the local Walker / Elephant setup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
ELEPHANT_MENUS="${HOME}/.config/elephant/menus"
WALKER_CONFIG="${HOME}/.config/walker/config.toml"

mkdir -p "$BIN_DIR" "$ELEPHANT_MENUS"

ln -sfn "$ROOT/bin/multica-quick-add" "$BIN_DIR/multica-quick-add"
chmod +x "$ROOT/bin/multica-quick-add" "$ROOT/bin/multica-quick-add"

# Hub + submenus + shared helpers
for f in \
  _multica_common.lua \
  multicaquickadd.lua \
  multicaworkspace.lua \
  multicaproject.lua \
  multicacreatedby.lua
do
  ln -sfn "$ROOT/elephant/menus/$f" "$ELEPHANT_MENUS/$f"
done

# Walker: ensure the menu provider is listed (idempotent)
if [[ -f "$WALKER_CONFIG" ]]; then
  if ! grep -q 'menus:multicaquickadd' "$WALKER_CONFIG"; then
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
  hub:     $ELEPHANT_MENUS/multicaquickadd.lua
  menus:   workspace · project · created-by (+ _multica_common.lua)

Usage:
  multica-quick-add --hub          # open Multica hub (recommended)
  multica-quick-add                # capture with last selection
  walker -m menus:multicaquickadd
  type prefix: mqa

Suggested niri bind:
  Super+Shift+Space {
    spawn-sh "multica-quick-add --hub";
  }

Requires Multica CLI login:
  multica setup
EOF
