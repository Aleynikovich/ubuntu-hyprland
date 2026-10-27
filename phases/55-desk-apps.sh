#!/usr/bin/env bash
# Desk apps: Slack, WhatsApp, Gmail, Linear, Notion as Vivaldi app windows with a home workspace and a jump key each.
# Why: as Vivaldi tabs they can't be told apart, so they can't have a fixed place. templates/scripts/desk-app.sh opens each one as an app
#   window (its own class) on its home workspace and jumps to it from anywhere, on either monitor. Apps and home workspaces are listed in
#   the script, keys in the keybinds block below.
# Rollback: remove the desk-app blocks from ~/.config/hypr/custom/keybinds.lua and rules.lua, and ~/.config/hypr/custom/scripts/desk-app.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

step "desk-app script"
install -Dm755 "$(dirname "$0")/../templates/scripts/desk-app.sh" ~/.config/hypr/custom/scripts/desk-app.sh

step "Jump keys"
BINDS="$HOME/.config/hypr/custom/keybinds.lua"
if grep -q desk-app.sh "$BINDS" 2>/dev/null; then
  # Installs from before Gmail: add its entry to the table
  grep -q '"gmail"' "$BINDS" || sed -i 's/{ "N", "notion", "Notion" } }/{ "N", "notion", "Notion" }, { "E", "gmail", "Gmail" } }/' "$BINDS"
  echo "binds already present"
else
  cat >> "$BINDS" <<'EOF2'

-- Desk apps (custom/scripts/desk-app.sh): SUPER+ALT+key jumps to the app (opens it on its home workspace if it isn't running; again on it
-- cycles its windows, or goes back if there is only one). SUPER+SHIFT+ALT+key opens another window of it on this workspace.
-- Ordered (pairs() isn't) so the cheatsheet (SUPER+/) lists them in this order, under "Desk".
for _, d in ipairs({ { "C", "slack", "Slack" }, { "W", "whatsapp", "WhatsApp" }, { "L", "linear", "Linear" }, { "N", "notion", "Notion" }, { "E", "gmail", "Gmail" } }) do
    local key, app, name = d[1], d[2], d[3]
    hl.bind("SUPER + ALT + " .. key, hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/desk-app.sh " .. app), { description = "Desk: " .. name })
    hl.bind("SUPER + SHIFT + ALT + " .. key, hl.dsp.exec_cmd("~/.config/hypr/custom/scripts/desk-app.sh " .. app .. " new"),
        { description = "Desk: New " .. name .. " window here" })
end
EOF2
fi

step "Opaque app windows"
# Their class is vivaldi-<host>__<path>-<profile>, which the vivaldi-stable rule (no blur, opaque) doesn't match.
RULES="$HOME/.config/hypr/custom/rules.lua"
if grep -q 'desk-app' "$RULES" 2>/dev/null; then echo "rule already present"; else
  cat >> "$RULES" <<'EOF2'
-- Vivaldi app windows (custom/scripts/desk-app.sh): opaque, no blur, like the browser itself
hl.window_rule({match = { class = "^vivaldi-.*__.*$" }, no_blur = true, opacity = 1})
EOF2
fi
step "Link router"
# Default http(s) handler: Linear/Notion/Gmail links open in their app window on its desk, the rest in Vivaldi (templates/scripts/link-router.sh).
# text/html (local files) stays with Vivaldi. Rollback: xdg-mime default vivaldi-stable.desktop x-scheme-handler/http x-scheme-handler/https
install -Dm755 "$(dirname "$0")/../templates/scripts/link-router.sh" ~/.config/hypr/custom/scripts/link-router.sh
cat > ~/.local/share/applications/link-router.desktop <<EOF2
[Desktop Entry]
Type=Application
Name=Link Router
Comment=Desk app links to their app window, the rest to Vivaldi
Exec=$HOME/.config/hypr/custom/scripts/link-router.sh %u
Icon=vivaldi
MimeType=x-scheme-handler/http;x-scheme-handler/https;
NoDisplay=true
EOF2
update-desktop-database ~/.local/share/applications 2>/dev/null || true
xdg-mime default link-router.desktop x-scheme-handler/http x-scheme-handler/https
ok "SUPER+ALT+C/W/E/L/N: Slack, WhatsApp, Gmail, Linear, Notion (Hyprland reloads the binds on save); Linear/Notion/Gmail links open on their desk"
