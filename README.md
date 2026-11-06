# fleet-compose

Docker Compose stacks for the three home machines, with secrets encrypted in-repo using `ansible-vault`.

| machine     | was       | dir                   |
|-------------|-----------|-----------------------|
| beefunk     | beefunk   | `machines/beefunk/`   |
| brownfunk   | bfunk     | `machines/brownfunk/` |
| evryfunk    | efunk     | `machines/evryfunk/`  |
| evryfunknuc    | evryfunknuc  | `machines/evryfunknuc/`  |
| brownfunk-nas   | VM of the same name (Fleet-Control) | `machines/brownfunk-nas/`   |
| brownfunk-media | VM of the same name (Fleet-Control) | `machines/brownfunk-media/` |
| beefunk-nas     | VM of the same name (Fleet-Control) | `machines/beefunk-nas/`     |
| beefunk-media   | VM of the same name (Fleet-Control) | `machines/beefunk-media/`   |

`<host>-nas` / `<host>-media` are the VMs that [Fleet-Control](https://github.com/lbesnard/Fleet-Control) (terraform + ansible) creates on the Proxmox hosts `brownfunk` / `beefunk`. They replace the single-machine `brownfunk` / `beefunk` stacks, which are kept until the migration is done. There is no `-net` VM.

- **nas** (`/media/<disk>/...`, the real disks): samba, rsync-server, scrutiny. No traefik; scrutiny is published on 8033 and routed from the media VM.
- **media** (`/mnt/nfs/<key>/...`, mounted from the NAS): everything else, including traefik, pihole, wireguard and duckdns. Local DNS records are in `pihole/etc-dnsmasq.d/02-custom.conf`; Ansible adds a generated, gitignored `05-lan.conf` next to it.
- **jellyfin** runs in its own LXC. Traefik routes to it (and to scrutiny on the NAS) from `traefik/dynamic_tls.yml`; the IPs there are hardcoded because the file provider cannot read `.env`.
- Which folders are exported and which `*_PATH` maps to what is defined in the Fleet-Control vault (`vars/paths.yml`, `storage_map`). Fleet-Control clones this repo on each VM and runs `install.sh --machine <host>-<type>`.
- Hard-coded IPs (VM/LXC/Tailscale addresses in `.env`, pihole, traefik, monitoring) are found and changed in both repos by `Fleet-Control/scripts/change-ip.sh` (`--list`, then `OLD NEW [--apply]`).

Each machine dir holds `docker-compose/…`. Secrets are committed as `<file>.vault`; the plaintext is gitignored.
`secrets.yml` lists which files are secret; `vendor.yml` pins third-party repos (ifm, explorer, homer-icons) that are cloned, not committed.

## New machine

```sh
git clone git@github.com:lbesnard/fleet-compose.git && cd fleet-compose
./install.sh
```

`install.sh` only decrypts; it never runs docker. It installs ansible/git if missing (asks first), resolves the machine, prompts for the vault password and checks it against a real vault file before saving it to `~/.config/fleet-compose/vault-pass`, installs the pre-commit hook (if `pre-commit` is available), then decrypts the secrets and clones the vendored repos. Options: `--machine NAME`, `--yes` (no prompts), and `FLEET_VAULT_PASS` for a non-interactive password.

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

Commits are checked by [pre-commit](https://pre-commit.com) (`.pre-commit-config.yaml`): staged plaintext secrets, unencrypted `.vault` files (`scripts/check-secrets.sh`), invalid YAML and merge-conflict markers are refused. Install once with `pipx install pre-commit` (or `brew install pre-commit`) then `pre-commit install`; `install.sh` runs the latter. Check everything with `pre-commit run --all-files`.

## Rotating TLS keys / ACME account

If `acme.json` or a `certs/*.key` leaked, see [docs/rotate-tls-and-acme.md](docs/rotate-tls-and-acme.md) (revoke, force a new account, regenerate, re-vault).

## The vault password

`~/.config/fleet-compose/vault-pass` is the single key to everything. It is **not** in the repo.
Lose it and the `.vault` files are unrecoverable, so keep a copy in your password manager.

## Shell completion

`./fleet <TAB>` completes subcommands, machine names (read from `machines/`) and, for `edit`, `.vault` files.

**zsh**

```sh
cp completions/_fleet ~/.zsh_complete/      # any directory on $fpath, file must be named _fleet
rm -f ~/.zcompdump*; exec zsh               # rebuild the completion cache
```

If your `compinit` runs with `-C` (cached), it will not see new completion files until the cache is deleted, hence the `rm`.

**bash**

```sh
echo "source $PWD/completions/fleet.bash" >> ~/.bashrc
```

Both work for `fleet` (if it is on your `PATH`) and `./fleet`. Outside the repo, put `fleet` on your `PATH` or set `FLEET_DIR=/path/to/fleet-compose` so machine names can be found; otherwise a built-in list is used.

## Glossary

| term | meaning |
|------|---------|
| **machine** | one of the hosts in the table above. Each has its own dir under `machines/` and its own stack. `all` means every machine. |
| **stack** | the set of containers described by a machine's `docker-compose.yml`. |
| **secret** | a file listed in `secrets.yml` (`.env`, `acme.json`, keys, ...). Committed only in encrypted form. |
| **vault file** (`*.vault`) | the encrypted copy of a secret, made by `ansible-vault`. This is what lives in git. |
| **plaintext** | the decrypted secret next to it. Gitignored and never committed. |
| **vault password** | the one passphrase that encrypts and decrypts every `.vault` file (see below). |
| **decrypt / encrypt** | `.vault` to plaintext / plaintext to `.vault`. `encrypt` only rewrites files that changed. |
| **vendored repo** | a third-party git repo (homer-icons, explorer, ifm) that a stack needs but that is not ours to commit here. `vendor.yml` lists each one with a URL and an exact commit; `./fleet vendor` clones it into the machine dir at that commit. The clones are gitignored, so builds are reproducible without copying someone else's code into this repo. |
| **sync** | `decrypt` + `vendor`: bring a fresh checkout to a runnable state. |
| **pre-commit hook** | `.pre-commit-config.yaml`; refuses commits that contain plaintext secrets, unencrypted `.vault` files or invalid YAML. |

### keygen vs rekey

Both deal with the vault password, at different moments.

- **`./fleet keygen`**: first time only. Creates a new random password in `~/.config/fleet-compose/vault-pass`. It refuses to run if that file already exists. Use it when starting a brand-new vault with nothing encrypted yet.
- **`./fleet rekey`**: the vault already exists and you want a *different* password (leaked, rotated, ...). It re-encrypts every `.vault` file under the new password, saves the new password as the key, and keeps the old one at `vault-pass.old`. Afterwards commit the re-encrypted files and copy the new password to your other machines.

In short: `keygen` makes the first key, `rekey` replaces an existing one.
