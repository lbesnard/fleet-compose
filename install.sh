#!/usr/bin/env bash
# Decrypt this machine's secrets and fetch vendored repos. Does not touch docker.
#   ./install.sh [--machine NAME] [--yes]
#   FLEET_VAULT_PASS=... ./install.sh   # non-interactive vault password
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

KEY="$HOME/.config/fleet-compose/vault-pass"
machine=${FLEET_MACHINE:-}; yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --machine) machine=${2:?}; shift 2 ;;
    --yes|-y) yes=1; shift ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
ask() { [ "$yes" = 1 ] && return 0; read -r -p "$1 [y/N] " a; [[ $a =~ ^[Yy]$ ]]; }

# 1. dependencies
say "Checking dependencies"
missing=(); for c in git ansible-playbook ansible-vault; do command -v "$c" >/dev/null || missing+=("$c"); done
if [ ${#missing[@]} -gt 0 ]; then
  echo "missing: ${missing[*]}"
  if command -v brew >/dev/null; then inst=(brew install ansible git)
  elif command -v apt-get >/dev/null; then inst=(sudo apt-get install -y ansible git)
  else echo "install ansible and git, then re-run" >&2; exit 1; fi
  ask "Run: ${inst[*]} ?" || exit 1
  "${inst[@]}"
fi

# 2. machine: --machine, $FLEET_MACHINE, saved choice, else ask. Hostnames are not used.
CHOICE="$HOME/.config/fleet-compose/machine"
[ -z "$machine" ] && [ -f "$CHOICE" ] && machine=$(cat "$CHOICE")
if [ -z "$machine" ]; then
  mapfile -t names < <(cd machines && ls -d */ | tr -d /)
  echo "Which machine is this?"
  select machine in "${names[@]}"; do [ -n "$machine" ] && break; done
fi
[ -d "machines/$machine" ] || { echo "unknown machine: $machine" >&2; exit 1; }
say "Machine: $machine"

# 3. vault password (verified against a real vault file before it is kept)
probe=$(find "machines/$machine" -name '*.vault' | head -n1)
[ -n "$probe" ] || { echo "no .vault files for $machine" >&2; exit 1; }
check() { ansible-vault view --vault-password-file "$1" "$probe" >/dev/null 2>&1; }

if [ -f "$KEY" ] && check "$KEY"; then
  say "Vault password found at $KEY"
else
  [ -f "$KEY" ] && echo "Existing $KEY does not decrypt the vaults."
  say "Vault password needed"
  tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT; chmod 600 "$tmp"
  if [ -n "${FLEET_VAULT_PASS:-}" ]; then printf '%s\n' "$FLEET_VAULT_PASS" > "$tmp"
  else read -r -s -p "Paste vault password: " p; echo; printf '%s\n' "$p" > "$tmp"; fi
  check "$tmp" || { echo "Wrong vault password." >&2; exit 1; }
  install -d -m 700 "$(dirname "$KEY")"; install -m 600 "$tmp" "$KEY"
  echo "saved to $KEY"
fi

git config core.hooksPath .githooks
install -d -m 700 "$(dirname "$CHOICE")"; echo "$machine" > "$CHOICE"

# 4. decrypt + vendor
say "Decrypting secrets and fetching vendored repos"
./fleet sync "$machine"

dir="machines/$machine/docker-compose"
say "Done. Secrets decrypted in $dir (run docker compose there yourself)."
