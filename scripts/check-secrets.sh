#!/usr/bin/env bash
# Refuse plaintext secrets and unencrypted .vault files. Called by pre-commit with the staged file names.
bad=0
for f in "$@"; do
  case "$f" in
    *.vault) head -c 15 "$f" | grep -q '^\$ANSIBLE_VAULT' || { echo "NOT ENCRYPTED: $f"; bad=1; } ;;
    */.env|*/acme.json|*.key|*/telegraf.conf) echo "PLAINTEXT SECRET staged: $f"; bad=1 ;;
  esac
done
exit $bad
