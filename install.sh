#!/usr/bin/env bash
# Install Multica Quick Add (Quickshell default + GTK comparison + optional Walker hub).
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
QS_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/multica-quick-add"
ELEPHANT_MENUS="${HOME}/.config/elephant/menus"
SHARE_DIR="${HOME}/.local/share/multica-quick-add"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/multica-quick-add"
SYSTEMD_USER="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mkdir -m 700 -p "$BIN_DIR" "$QS_CFG" "$SHARE_DIR" "$ELEPHANT_MENUS" "$SYSTEMD_USER" "$STATE_DIR" "$STATE_DIR/cache"
chmod 700 "$STATE_DIR" "$STATE_DIR/cache" 2>/dev/null || true

# CLI
ln -sfn "$ROOT/bin/multica-quick-add" "$BIN_DIR/multica-quick-add"
ln -sfn "$ROOT/bin/mqa-bootstrap" "$BIN_DIR/mqa-bootstrap"
chmod +x "$ROOT/bin/multica-quick-add" "$ROOT/bin/mqa-bootstrap" \
  "$ROOT/panel/gtk/multica_quick_add_panel.py"

# Quickshell config
ln -sfn "$ROOT/panel/quickshell/shell.qml" "$QS_CFG/shell.qml"

# Optional Walker hub assets
ln -sfn "$ROOT/elephant/lib/multica_common.lua" "$SHARE_DIR/multica_common.lua"
rm -f "$ELEPHANT_MENUS/_multica_common.lua"
for f in multicaquickadd.lua multicaworkspace.lua multicaproject.lua multicacreatedby.lua; do
  ln -sfn "$ROOT/elephant/menus/$f" "$ELEPHANT_MENUS/$f"
done

QS_BIN="$(command -v qs || true)"
if [[ -n "$QS_BIN" ]]; then
  cat >"$SYSTEMD_USER/multica-quick-add-qs.service" <<EOF
[Unit]
Description=Multica Quick Add (Quickshell panel daemon)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${QS_BIN} -c multica-quick-add -n
Restart=on-failure
RestartSec=2
Environment=QT_QPA_PLATFORM=wayland
Environment=BASH_ENV=

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable multica-quick-add-qs.service 2>/dev/null || true
  systemctl --user restart multica-quick-add-qs.service 2>/dev/null || {
    if ! qs list --all 2>/dev/null | grep -qi multica-quick-add; then
      qs -c multica-quick-add -n -d >/dev/null 2>&1 || true
    fi
  }
else
  echo "note: qs not found — Quickshell daemon unit not installed" >&2
fi

cat <<EOF

Installed:
  $BIN_DIR/multica-quick-add
  $BIN_DIR/mqa-bootstrap
  Quickshell: $QS_CFG/shell.qml
  GTK panel:  $ROOT/panel/gtk/multica_quick_add_panel.py (comparison only)
  systemd:    multica-quick-add-qs.service

Open:
  multica-quick-add --panel       # Quickshell layer-shell (default)
  multica-quick-add --panel-gtk   # GTK comparison
  multica-quick-add --hub         # Walker legacy hub

Suggested niri bind:
  Super+Shift+Space {
    spawn-sh "multica-quick-add --panel";
  }

Optional niri window rule (if layer-shell is unavailable and FloatingWindow is used):
  // match app-id of qs instance if needed
EOF
