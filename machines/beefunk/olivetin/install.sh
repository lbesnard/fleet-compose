#!/bin/sh
# Run on beefunk with: sudo ./install.sh   (after installing the OliveTin .deb, see README.md)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
command -v OliveTin >/dev/null || [ -x /usr/local/bin/OliveTin ] || { echo "OliveTin is not installed (see README.md)" >&2; exit 1; }

grep -q REPLACE_WITH_ARGON2ID_HASH "$here/config.yaml" && { echo "set the login hash in config.yaml first (README.md, 'Auth')" >&2; exit 1; }
[ -r /home/lbesnard/.ssh/olivetin_ed25519 ] || echo "warning: ~/.ssh/olivetin_ed25519 missing, rclone/rsync buttons will fail (README.md, 'SSH key')" >&2

install -o root -g root -m 0755 "$here/docker-logs-truncate" /usr/local/sbin/docker-logs-truncate

install -o root -g root -m 0440 "$here/sudoers-olivetin" /etc/sudoers.d/olivetin.new
visudo -cf /etc/sudoers.d/olivetin.new
mv /etc/sudoers.d/olivetin.new /etc/sudoers.d/olivetin

install -d /etc/systemd/system/OliveTin.service.d
install -m 0644 "$here/olivetin-user.conf" /etc/systemd/system/OliveTin.service.d/user.conf

install -d /etc/OliveTin
ln -sf "$here/config.yaml" /etc/OliveTin/config.yaml   # symlink: `git pull` updates the config

# the service user must be able to run docker
id -nG lbesnard | tr ' ' '\n' | grep -qx docker || usermod -aG docker lbesnard

sudo -u lbesnard "$here/gen-funk-entities.sh"
OliveTin -configdir /etc/OliveTin -syntaxcheck && echo "config syntax ok"
systemctl daemon-reload
systemctl enable --now OliveTin
systemctl restart OliveTin
systemctl --no-pager status OliveTin | head -5
