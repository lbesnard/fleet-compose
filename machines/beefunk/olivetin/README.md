# OliveTin on beefunk

Runs natively (systemd) as `lbesnard`, not in a container: the actions use host paths, `~/.alias_sync`
(zsh functions), host ssh keys, the docker group and `/media/*` disks. See
<https://docs.olivetin.app/install/container_vs_service.html>.

## Install (on beefunk)

```sh
wget https://github.com/OliveTin/OliveTin/releases/latest/download/OliveTin_linux_amd64.deb
sudo dpkg -i OliveTin_linux_amd64.deb
cd ~/github_repo/fleet-compose/machines/beefunk/olivetin && sudo ./install.sh
```

`install.sh` installs the `docker-logs-truncate` wrapper plus a sudoers rule allowing only that script, a systemd
drop-in (`User=lbesnard`, PATH incl. brew), symlinks `config.yaml` into `/etc/OliveTin`, builds the task list,
runs `-syntaxcheck` and starts the service. 

## URL and auth

`https://olivetin.funkybeefunk.duckdns.org` goes through traefik (`traefik/dynamic_tls.yml`: router `olivetin`,
service `olivetin-host` -> `http://beefunk.lan:1337`) and has a Dashy tile. DNS already covers
`*.funkybeefunk.duckdns.org`. OliveTin does its own login and denies everything by default (`defaultPermissions`
all false, `admins` ACL), so port 1337 stays safe even when reached directly on the LAN.

`config.yaml` holds the password hash, so it is a vaulted secret (`secrets.yml`). To set it:

```sh
# the hash helper is an API endpoint of a running OliveTin, so use any instance (or the one on another host):
curl -sS --json '{"password": "CHANGE_ME"}' http://localhost:1337/api/PasswordHash
# paste it in config.yaml (replace REPLACE_WITH_ARGON2ID_HASH), then from the repo root:
./fleet encrypt && git add -A && git commit
# on beefunk after git pull:
./fleet decrypt
```

Chicken and egg: the hash endpoint needs a running OliveTin. Install the package first (it starts with its example
config), call the endpoint, then run `install.sh`.

## SSH key

The service has no ssh-agent, so it uses a dedicated passphrase-less key (`FUNK_SSH_KEY`, set in the systemd
drop-in; `funk_rclone` and the rsync button use it, and interactive shells are unaffected):

```sh
ssh-keygen -t ed25519 -N '' -C olivetin@beefunk -f ~/.ssh/olivetin_ed25519
# authorize ~/.ssh/olivetin_ed25519.pub on each source server for the rclone `backup` user (port 9000)
# and on evryfunk for the rsync, ideally restricted: from="<beefunk LAN IP>",no-pty,no-port-forwarding,no-X11-forwarding
```

Anyone who gets a shell as `lbesnard` on beefunk can read that key, so keep the restrictions on the server side.
A passphrase prompt is not possible from OliveTin; the alternative is an "unlock key" action taking the passphrase as
a `password` argument and feeding `ssh-add` via `SSH_ASKPASS`, but the key then vanishes at every reboot or timeout.

## rclone tasks

`gen-funk-entities.sh` turns `funk_rclone_task --list-jsonl` (tasks of this host whose destination disk is mounted)
into `~/.local/share/olivetin/funk_tasks.jsonl`: one button per task, rebuilt at service start, after each sync and
by the "Refresh backup task list" button. rclone goes over ssh with the dedicated key above.

## Unverified (written from the docs, not run)

* `timeout:` unit (seconds assumed), entity fieldset layout, `{{ .Arguments.x }}` / `{{ .CurrentEntity.x }}` inside
  `exec:`/`shell:`. Run `OliveTin -configdir /etc/OliveTin -syntaxcheck` and click through each button once.
* Paths assume the repo is checked out at `/home/lbesnard/github_repo/fleet-compose` on beefunk.
