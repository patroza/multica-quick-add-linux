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

# Shared Lua helper — NOT under menus/ (Elephant loads every .lua there as a menu).
ln -sfn "$ROOT/elephant/lib/multica_common.lua" "$SHARE_DIR/multica_common.lua"
rm -f "$ELEPHANT_MENUS/_multica_common.lua"

for f in multicaquickadd.lua multicaworkspace.lua multicaproject.lua multicacreatedby.lua; do
  ln -sfn "$ROOT/elephant/menus/$f" "$ELEPHANT_MENUS/$f"
done

ensure_walker_block() {
  local marker="$1"
  local block="$2"
  if [[ ! -f "$WALKER_CONFIG" ]]; then
    return 0
  fi
  if grep -Fq "$marker" "$WALKER_CONFIG"; then
    return 0
  fi
  printf '\n%s\n' "$block" >>"$WALKER_CONFIG"
  echo "Updated $WALKER_CONFIG ($marker)"
}

if [[ -f "$WALKER_CONFIG" ]]; then
  if ! grep -q 'menus:multicaquickadd' "$WALKER_CONFIG"; then
    if grep -q 'installed_providers' "$WALKER_CONFIG"; then
      tmp="$(mktemp)"
      awk '
        BEGIN { done=0 }
        /installed_providers/ { inarr=1 }
        inarr && /^\s*\]/ && !done {
          print "  \"menus:multicaquickadd\","
          print "  \"menus:multicaworkspace\","
          print "  \"menus:multicaproject\","
          print "  \"menus:multicacreatedby\","
          done=1
        }
        { print }
      ' "$WALKER_CONFIG" >"$tmp"
      mv "$tmp" "$WALKER_CONFIG"
      echo "Added Multica menus to installed_providers"
    fi
  fi

  # Ensure child menus are listed (idempotent lines)
  for child in multicaworkspace multicaproject multicacreatedby; do
    if ! grep -q "menus:$child" "$WALKER_CONFIG"; then
      # insert before closing of installed_providers if possible
      if grep -q 'installed_providers' "$WALKER_CONFIG"; then
        tmp="$(mktemp)"
        awk -v child="$child" '
          /installed_providers/ { inarr=1 }
          inarr && /^\s*\]/ && !done {
            print "  \"menus:" child "\","
            done=1
          }
          { print }
        ' "$WALKER_CONFIG" >"$tmp"
        mv "$tmp" "$WALKER_CONFIG"
      fi
    fi
  done

  ensure_walker_block 'provider = "menus:multicaquickadd"' \
'[providers.prefixes]
prefix = "mqa"
provider = "menus:multicaquickadd"'

  # Provider set: hub is the landing page, but NOT exclusive (-m).
  # Child menus must be queryable when elephant switches provider.
  ensure_walker_block 'providers.sets.multica' \
'[providers.sets.multica]
default = ["menus:multicaquickadd"]
empty = ["menus:multicaquickadd"]'

  # send = submit issue (Close); open = open picker / refresh (stay open).
  # ctrl+w/p/t = jump to workspace/project/agent even while a row is focused.
  ensure_walker_block 'menus:multicaquickadd" =' \
'[providers.actions]
"menus:multicaquickadd" = [
  { action = "send", default = true, bind = "Return", after = "Close" },
  { action = "open", default = true, bind = "Return", after = "Nothing" },
  { action = "open_workspace", label = "workspace", bind = "ctrl w", after = "Nothing" },
  { action = "open_project", label = "project", bind = "ctrl p", after = "Nothing" },
  { action = "open_createdby", label = "agent", bind = "ctrl t", after = "Nothing" },
  { action = "menus:parent", label = "back", bind = "Escape", after = "Nothing" },
]
"menus:multicaworkspace" = [
  { action = "open", default = true, bind = "Return", after = "Nothing" },
  { action = "menus:parent", label = "back", bind = "Escape", after = "Nothing" },
]
"menus:multicaproject" = [
  { action = "open", default = true, bind = "Return", after = "Nothing" },
  { action = "menus:parent", label = "back", bind = "Escape", after = "Nothing" },
]
"menus:multicacreatedby" = [
  { action = "open", default = true, bind = "Return", after = "Nothing" },
  { action = "menus:parent", label = "back", bind = "Escape", after = "Nothing" },
]'
else
  echo "No $WALKER_CONFIG found — skip walker wiring"
fi

if command -v omarchy-restart-walker >/dev/null 2>&1; then
  omarchy-restart-walker || true
else
  systemctl --user try-restart elephant.service 2>/dev/null || true
fi

cat <<EOF

Installed:
  $BIN_DIR/multica-quick-add
  hub:     $ELEPHANT_MENUS/multicaquickadd.lua
  helper:  $SHARE_DIR/multica_common.lua

Usage:
  multica-quick-add --hub     # walker -s multica (not exclusive -m)
  Type an issue, Enter to send
  ctrl+w workspace · ctrl+p project · ctrl+t agent

If Walker was broken: omarchy-restart-walker
EOF
