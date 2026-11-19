#!/bin/sh
# Regenerate the OliveTin entity file listing the rclone backup tasks usable on this machine
# (destination mounted). Output is JSON Lines, one task per line, as OliveTin expects.
# Rewritten IN PLACE (">") so OliveTin's file watcher keeps seeing the same inode.
set -eu
out="${1:-$HOME/.local/share/olivetin/funk_tasks.jsonl}"
mkdir -p "$(dirname "$out")"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

zsh -c 'source "$HOME/.alias_sync"; funk_rclone_task --list-jsonl' \
  | jq -c 'select(.name | contains("'"'"'") | not)
           | . + {label: "\(.source) → \(.destination)  (\(.last_sync))"}' > "$tmp"

# A name with a single quote would break out of the quoting in config.yaml: report it, never expose it.
zsh -c 'source "$HOME/.alias_sync"; funk_rclone_task --list-jsonl' \
  | jq -r 'select(.name | contains("'"'"'")) | "skipped (contains a quote): \(.name)"' >&2 || true

cat "$tmp" > "$out"
echo "$(wc -l < "$out") tasks -> $out"
