#!/usr/bin/env bash
# OPTIONAL: VS Code from Microsoft's apt repo (no snap/flatpak), plus secret-tool. Key is checked against
# Microsoft's published fingerprint before it is trusted.
# Also installs templates/vscode (settings if none exist, extensions). Rollback: sudo apt-get purge $(cat "$SRC/apt-installed-vscode.txt") && sudo rm /etc/apt/sources.list.d/vscode.sources /etc/apt/keyrings/packages.microsoft.gpg
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

EXPECTED_FPR=BC528686B50D79E339D3721CEB3E94ADBE1229CF
tmp=$(mktemp); at_exit 'rm -f "$tmp"'
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$tmp"
fpr=$(gpg --show-keys --with-colons "$tmp" | awk -F: '/^fpr/{print $10; exit}')
[ "$fpr" = "$EXPECTED_FPR" ] || die "Microsoft key fingerprint mismatch: $fpr"
ok "Microsoft key fingerprint OK"

sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 "$tmp" /etc/apt/keyrings/packages.microsoft.gpg
sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/packages.microsoft.gpg
EOF
# Otherwise the package's postinst adds a duplicate vscode.list ("configured multiple times" apt errors).
echo "code code/add-microsoft-repo boolean false" | sudo debconf-set-selections
sudo apt-get update
mkdir -p "$SRC"
apt_install_new_only "$SRC/apt-installed-vscode.txt" code libsecret-tools

# Hyprland isn't recognised as a desktop by VS Code's keyring detection: force gnome-keyring (libsecret).
A=$HOME/.vscode/argv.json
if [ -f "$A" ] && ! grep -q '"password-store"' "$A"; then
  cp "$A" "$A.bak"
  python3 - "$A" <<'EOF'
import re,sys
p=sys.argv[1]; s=open(p).read()
i=s.rstrip().rfind('}')
body=s[:i].rstrip()
sep='' if body.endswith('{') else ','
open(p,'w').write(body+sep+'\n\n\t// Hyprland is not auto-detected; always use gnome-keyring (libsecret) for logins.\n\t"password-store": "gnome-libsecret"\n}\n')
EOF
elif [ ! -f "$A" ]; then
  mkdir -p "$(dirname "$A")"; printf '{\n\t"password-store": "gnome-libsecret"\n}\n' > "$A"
fi
code --version | head -1
ok "VS Code installed (updates come with apt upgrade)."

step "VS Code settings and extensions (templates/vscode)"
# Settings only if there are none yet (never overwrite yours); extensions are installed if missing.
# The repo copy leaves out machine-specific paths, the cloud project id and the terminal auto-approve list on purpose.
UD="$HOME/.config/Code/User"
install -d "$UD"
if [ -s "$UD/settings.json" ]; then echo "settings.json exists, left alone (reference copy: templates/vscode/settings.json)"; else
  install -m644 "$(dirname "$0")/../templates/vscode/settings.json" "$UD/settings.json"
fi
have=$(code --list-extensions 2>/dev/null || true)
while read -r ext; do
  [ -n "$ext" ] || continue
  echo "$have" | grep -qix "$ext" || code --install-extension "$ext" >/dev/null 2>&1 || warn "could not install $ext"
done < "$(dirname "$0")/../templates/vscode/extensions.txt"
ok "VS Code settings in place; extensions from templates/vscode/extensions.txt installed."
