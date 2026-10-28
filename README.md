# fleet-compose

Docker Compose stacks for the three home machines, with secrets encrypted in-repo using `ansible-vault`.

| machine     | was       | dir                   |
|-------------|-----------|-----------------------|
| beefunk     | beefunk   | `machines/beefunk/`   |
| brownfunk   | bfunk     | `machines/brownfunk/` |
| evryfunk    | efunk     | `machines/evryfunk/`  |
| evryfunknuc    | evryfunknuc  | `machines/evryfunknuc/`  |

Each machine dir holds `docker-compose/…`. Secrets are committed as `<file>.vault`; the plaintext is gitignored.
`secrets.yml` lists which files are secret; `vendor.yml` pins third-party repos (ifm, explorer, homer-icons) that are cloned, not committed.

## New machine

```sh
git clone git@github.com:lbesnard/fleet-compose.git && cd fleet-compose
./install.sh
```

`install.sh` only decrypts; it never runs docker. It installs ansible/git if missing (asks first), resolves the machine, prompts for the vault password and checks it against a real vault file before saving it to `~/.config/fleet-compose/vault-pass`, enables the git hook, then decrypts the secrets and clones the vendored repos. Options: `--machine NAME`, `--yes` (no prompts), and `FLEET_VAULT_PASS` for a non-interactive password.

Machine: `--machine NAME`, else `$FLEET_MACHINE`, else the choice saved from a previous run (`~/.config/fleet-compose/machine`), else a menu. Hostnames are not used. After that, `./fleet sync` and `./fleet decrypt` need no argument.

Then start the stack yourself: `cd machines/<name>/docker-compose && docker compose up -d`.

## Deploying a change

Ansible does not deploy anything: it only decrypts secrets and clones vendored repos. The checkout *is* the deployment.

- **Plain file changed** (not in `secrets.yml`): `git pull`, then `docker compose up -d` in `machines/<name>/docker-compose`.
- **Secret changed**: on the editing machine `./fleet encrypt`, commit and push. On the target `git pull && ./fleet decrypt`, then `docker compose up -d`.

Warning: `./fleet decrypt` overwrites local plaintext with the vault content. Run `./fleet encrypt` and commit before decrypting if you edited a secret locally.

## Day to day

| task | command |
|------|---------|
| decrypt after pull | `./fleet decrypt` |
| edit a secret, plaintext edited in place | edit file, then `./fleet encrypt` (only changed files are re-encrypted) |
| edit straight in the vault | `./fleet edit machines/beefunk/docker-compose/.env.vault` |
| add a new secret file | add path to `secrets.yml`, create it, `./fleet encrypt` (also updates `.gitignore`) |
| decrypt elsewhere | `ansible-playbook playbooks/decrypt.yml -e machine=beefunk -e dest_root=/opt/stacks` |

The pre-commit hook blocks staged plaintext secrets and malformed `.vault` files.

## The vault password

`~/.config/fleet-compose/vault-pass` is the single key to everything. It is **not** in the repo.
Lose it and the `.vault` files are unrecoverable, so keep a copy in your password manager.
