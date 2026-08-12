#!/usr/bin/env bash
# Install Multica Quick Add into the local Walker / Elephant setup.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
ELEPHANT_MENUS="${HOME}/.config/elephant/menus"
SHARE_DIR="${HOME}/.local/share/multica-quick-add"
WALKER_CONFIG="${HOME}/.config/walker/config.toml"

mkdir -p "$BIN_DIR" "$ELEPHANT_MENUS" "$SHARE_DIR"

ln -sfn "$ROOT/bin/multica-quick-add" "$BIN_DIR/multica-quick-add"
chmod +x "$ROOT/bin/multica-quick-add"

# Shared Lua helper — NOT under menus/ (Elephant tries to load every .lua there as a menu).
ln -sfn "$ROOT/elephant/lib/multica_common.lua" "$SHARE_DIR/multica_common.lua"

# Remove stale common from menus if present (caused load errors / broken menu provider).
rm -f "$ELEPHANT_MENUS/_multica_common.lua"

# Hub + submenus
for f in multicaquickadd.lua multicaworkspace.lua multicaproject.lua multicacreatedby.lua; do
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

# Hard restart Elephant + Walker service so menus reload and stale clients die.
if command -v omarchy-restart-walker >/dev/null 2>&1; then
  omarchy-restart-walker || true
else
  systemctl --user try-restart elephant.service 2>/dev/null || true
  pkill -x elephant 2>/dev/null || true
  # walker service is a plain process on many setups
  pkill -x walker 2>/dev/null || true
fi

cat <<EOF

Installed:
  $BIN_DIR/multica-quick-add
  hub:     $ELEPHANT_MENUS/multicaquickadd.lua
  helper:  $SHARE_DIR/multica_common.lua
  menus:   workspace · project · created-by

Usage:
  multica-quick-add --hub
  walker -m menus:multicaquickadd
  type prefix: mqa

If Walker shows empty results: omarchy-restart-walker
EOF
