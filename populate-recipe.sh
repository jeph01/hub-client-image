#!/usr/bin/env bash
#
# populate-recipe.sh — writes the Hubelia client image recipe + config files.
# Run this ONCE from inside your cloned hub-client-image repo folder:
#     cd hub-client-image
#     bash populate-recipe.sh
# Then review (git status / git diff), commit, and push.
#
set -euo pipefail

echo "==> Creating folder structure"
mkdir -p recipes
mkdir -p files/system/etc/polkit-1/rules.d
mkdir -p files/system/etc/skel/.config
mkdir -p files/system/etc/skel/.local/share/konsole
mkdir -p files/system/etc/skel/.ssh

echo "==> Writing recipes/recipe.yml"
cat > recipes/recipe.yml <<'EOF'
---
# yaml-language-server: $schema=https://schema.blue-build.org/recipe-v1.json
# Hubelia managed client image (Aurora-based). Publishes to
# ghcr.io/<repo-owner>/hub-client-image
name: hub-client-image
description: Hubelia managed client (Aurora DX base)
base-image: ghcr.io/ublue-os/aurora-dx
image-version: stable

modules:
  # System packages layered onto the base (not shipped in stock Aurora)
  - type: rpm-ostree
    install:
      - syncthing        # file sync to the VPS
      - kio-extras       # enables sftp:// browsing in Dolphin

  # Default apps, installed system-wide (available to every account, admin-managed)
  - type: default-flatpaks
    configurations:
      - scope: system
        install:
          - dev.zed.Zed
          - us.zoom.Zoom
          - com.slack.Slack
          - org.signal.Signal
          - com.obsproject.Studio
          # Teams has no native Linux client — use the Teams PWA
          # (teams.microsoft.com -> Install as app), or add
          # com.github.IsmaelMartinez.teams_for_linux for a standalone wrapper.

  # Copy the baked-in config files (everything under files/system -> /)
  - type: files
    files:
      - source: system
        destination: /

  # Enable the Tailscale daemon at boot (auth 'tailscale up' is a first-login step)
  - type: systemd
    system:
      enabled:
        - tailscaled.service

  # Set up image signature verification (uses your cosign.pub)
  - type: signing
EOF

echo "==> Writing polkit rule (app install/uninstall needs admin approval)"
cat > files/system/etc/polkit-1/rules.d/49-flatpak-admin-only.rules <<'EOF'
// Non-admin (non-wheel) users must enter an admin password to
// install or uninstall Flatpak applications.
polkit.addRule(function(action, subject) {
  if (action.id.indexOf("org.freedesktop.Flatpak.") === 0 &&
      !subject.isInGroup("wheel")) {
    return polkit.Result.AUTH_ADMIN;
  }
});
EOF

echo "==> Writing Konsole default-VPS profile"
cat > files/system/etc/skel/.local/share/konsole/VPS.profile <<'EOF'
[General]
Name=VPS
Command=ssh hub-mtl-01
EOF

cat > files/system/etc/skel/.config/konsolerc <<'EOF'
[Desktop Entry]
DefaultProfile=VPS.profile
EOF

echo "==> Writing XDG user-dirs (all user folders -> ~/work, the synced folder)"
cat > files/system/etc/skel/.config/user-dirs.dirs <<'EOF'
XDG_DESKTOP_DIR="$HOME/work"
XDG_DOWNLOAD_DIR="$HOME/work"
XDG_DOCUMENTS_DIR="$HOME/work"
XDG_MUSIC_DIR="$HOME/work"
XDG_PICTURES_DIR="$HOME/work"
XDG_VIDEOS_DIR="$HOME/work"
XDG_TEMPLATES_DIR="$HOME/work"
XDG_PUBLICSHARE_DIR="$HOME/work"
EOF

echo "==> Writing SSH config skeleton (User omitted -> defaults to local username = VPS username)"
cat > files/system/etc/skel/.ssh/config <<'EOF'
Host hub-mtl-01
    HostName hub-mtl-01
EOF

# Tighten perms on the skel .ssh so new users get a well-formed ~/.ssh
chmod 700 files/system/etc/skel/.ssh
chmod 600 files/system/etc/skel/.ssh/config

echo
echo "==> Done. Files created:"
echo "    recipes/recipe.yml"
echo "    files/system/etc/polkit-1/rules.d/49-flatpak-admin-only.rules"
echo "    files/system/etc/skel/.local/share/konsole/VPS.profile"
echo "    files/system/etc/skel/.config/konsolerc"
echo "    files/system/etc/skel/.config/user-dirs.dirs"
echo "    files/system/etc/skel/.ssh/config"
echo
echo "Next: review with 'git status' and 'git diff', then commit & push."
echo "If the template shipped a sample recipe (e.g. recipes/recipe.yml already"
echo "existed with example content), this overwrote it — that's expected."
