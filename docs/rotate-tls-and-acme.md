# Rotating TLS keys and the ACME (Let's Encrypt) account

Use this when `acme.json` or a `certs/*.key` may have leaked (committed in plaintext, pasted somewhere,
a machine was compromised), or simply to start clean.

## What is what

| file (per machine, under `docker-compose/traefik/`) | what it holds | if it leaks |
|---|---|---|
| `acme/acme.json` | Let's Encrypt **account private key** + the issued public certificate(s) **and their private keys** (e.g. `funky<host>.duckdns.org`) | Someone can impersonate your public hostname and, while old DNS authorizations are still valid (up to 30 days), order certificates with your account. **Serious.** |
| `certs/<host>.key` (+ `.crt`) | Self-signed LAN certificate (`*.<host>.local/.home/.lan`), valid for years | LAN-only impersonation. Lower risk, still regenerate. |

Accounts are per host. Check which machines share one (same `acct` number means same account and certificate):

```sh
python3 - <<'PY'
import json,glob
for f in sorted(glob.glob('machines/*/docker-compose/traefik/acme/acme.json')):
    d=json.load(open(f))
    for v in d.values():
        acct=((v.get('Account') or {}).get('Registration') or {}).get('uri','').split('/')[-1]
        print(f.split('/')[1], 'acct', acct, [c['domain']['main'] for c in v.get('Certificates') or []])
PY
```

## 1. Revoke the leaked certificate (do this BEFORE deleting `acme.json`)

Revocation only needs the certificate and its own key, not the account. Use reason `keycompromise`.

```sh
cd machines/<machine>/docker-compose/traefik/acme
mkdir -p /tmp/rv
jq -r '.duckdns.Certificates[0].certificate' acme.json | base64 -d > /tmp/rv/c.pem
jq -r '.duckdns.Certificates[0].key'         acme.json | base64 -d > /tmp/rv/k.pem
certbot revoke --cert-path /tmp/rv/c.pem --key-path /tmp/rv/k.pem --reason keycompromise \
  --config-dir /tmp/rv/cb --work-dir /tmp/rv/cb --logs-dir /tmp/rv/cb
shred -u /tmp/rv/*.pem
```

Replace `duckdns` with the resolver name from the traefik command line (`--certificatesresolvers.<name>...`)
if you ever rename it. Machines sharing an account and certificate (e.g. `brownfunk` and `brownfunk-media`)
need this only once.

## 2. Force a new ACME account and certificate

There is no "register" command: Traefik creates a new account whenever `acme.json` contains none.

```sh
docker compose stop traefik
mv acme.json acme.json.old              # keep until the new cert works
install -m 600 /dev/null acme.json      # must exist, mode 600, empty
docker compose up -d traefik
docker logs -f traefik 2>&1 | grep -i -E "acme|certificate|error"
```

- Traefik registers with the email from its config and requests a cert via DNS-01 (needs the DuckDNS token in `.env`).
- The new certificate gets a new private key.
- Do **not** try the staging CA first: staging accounts are separate, so you would wipe `acme.json` again.
- Let's Encrypt allows **5 duplicate certificates per week** per exact hostname set. One clean run is fine; do not loop on failures.
- When the new cert is served, delete `acme.json.old` (`shred -u`).

## 3. The old account

The leaked account key remains valid until deactivated, but with the certificate revoked and a new account in
use, it can only order certs while its old DNS authorizations last (at most 30 days). Waiting is acceptable.

## 4. Regenerate the self-signed LAN certificate

Per affected host (adjust names):

```sh
cd machines/<machine>/docker-compose/traefik/certs
openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days 3650 -keyout <host>.key -out <host>.crt \
  -subj "/CN=<host>.local" \
  -addext "subjectAltName=DNS:<host>.local,DNS:*.<host>.local,DNS:<host>.home,DNS:*.<host>.home,DNS:<host>.lan,DNS:*.<host>.lan"
```

Re-trust the new `.crt` on every device that had imported the old one, then restart traefik.

## 5. Update the vault and push

```sh
./fleet encrypt <machine>      # refreshes acme.json.vault and <host>.key.vault
git add -A && git commit -m "Rotate TLS key and ACME account" && git push
```

On the other copies of the repo: `git pull && ./fleet decrypt <machine>`.

`acme.json` is regenerable state. If you would rather never store it, remove it from `secrets.yml`; the
cost is a fresh issuance on every rebuild (mind the 5-per-week limit).

## Checklist

- [ ] Leaked cert revoked (`keycompromise`)
- [ ] `acme.json` replaced, new account and certificate issued, site serves the new cert
- [ ] Self-signed LAN cert regenerated and re-trusted on devices
- [ ] `./fleet encrypt`, committed, pushed
- [ ] Old `acme.json.old` shredded
- [ ] If the secret was in a git repo: history rewritten (`git filter-repo --invert-paths --path <file>`), force-pushed, other clones reset
