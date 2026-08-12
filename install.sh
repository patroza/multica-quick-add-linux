#!/usr/bin/env bash
# Install Multica Quick Add (Quickshell panel + GTK panel + CLI + optional Walker hub).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
QS_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/multica-quick-add"
ELEPHANT_MENUS="${HOME}/.config/elephant/menus"
SHARE_DIR="${HOME}/.local/share/multica-quick-add"
SYSTEMD_USER="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mkdir -p "$BIN_DIR" "$QS_CFG" "$SHARE_DIR" "$ELEPHANT_MENUS" "$SYSTEMD_USER"

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

# User unit: keep Quickshell Multica panel daemon warm
cat >"$SYSTEMD_USER/multica-quick-add-qs.service" <<EOF
[Unit]
Description=Multica Quick Add (Quickshell panel daemon)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$(command -v qs) -c multica-quick-add -n
Restart=on-failure
RestartSec=2
Environment=QT_QPA_PLATFORM=wayland
Environment=BASH_ENV=

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now multica-quick-add-qs.service 2>/dev/null || {
  # fallback: start detached if systemd user session limited
  if command -v qs >/dev/null 2>&1; then
    if ! qs list --all 2>/dev/null | grep -qi multica-quick-add; then
      qs -c multica-quick-add -n -d >/dev/null 2>&1 || true
    fi
  fi
}

# niri bind helper text
cat <<EOF

Installed:
  $BIN_DIR/multica-quick-add
  $BIN_DIR/mqa-bootstrap
  Quickshell: $QS_CFG/shell.qml
  GTK panel:  $ROOT/panel/gtk/multica_quick_add_panel.py
  systemd:    multica-quick-add-qs.service (enable if graphical user session)

Open:
  multica-quick-add --panel       # Quickshell (recommended)
  multica-quick-add --panel-gtk   # GTK comparison
  multica-quick-add --hub         # Walker legacy hub

Suggested niri bind:
  Super+Shift+Space {
    spawn-sh "multica-quick-add --panel";
  }
EOF
