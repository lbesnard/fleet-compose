# Traefik setup for evryfunk

Traefik is the reverse proxy on evryfunk (same design as brownfunk and beefunk). It adds
HTTPS names for the services **without removing the direct ports**, so existing links like
`http://evryfunk.lan:8096` keep working.

## Addresses

| Name | Resolves to | Certificate |
|---|---|---|
| `<service>.funkyevryfunk.duckdns.org` | tailscale IP `100.65.194.124` (DuckDNS) | Let's Encrypt wildcard, valid |
| `<service>.evryfunk.lan` / `.home` / `.local` | LAN IP, needs LAN DNS (pihole) | self-signed, browser warning |
| `http://evryfunk.lan` (bare host) | LAN IP | none: plain http, serves **homer** |
| `evryfunk.lan:<port>` | LAN IP | none: direct container ports |

`home.funkyevryfunk.duckdns.org` and `dashy.funkyevryfunk.duckdns.org` open **dashy**.
`traefik.funkyevryfunk.duckdns.org` is the traefik dashboard.

DuckDNS wildcards resolve every subdomain of `funkyevryfunk` to the same IP, so no DNS record
is needed per service. The name only works for clients on the tailnet (or with pihole as
their DNS, see below).

## Files

| File | Role |
|---|---|
| `docker-compose.yml` | `traefik`, `dashy`, `homer`, `glances`, `wg-easy` services and labels |
| `traefik/dynamic_tls.yml` | certificates, http->https redirect, one router per service that has no labels, remote (brownfunk) services |
| `traefik/certs/evryfunk.{crt,key}` | self-signed cert for `*.evryfunk.{lan,home,local}` (key is a `.vault`) |
| `traefik/acme/acme.json` | Let's Encrypt storage, written by traefik (a `.vault`, must be mode 600) |
| `dashy/conf.yml` | dashy dashboard |
| `pihole/etc-dnsmasq.d/02-custom.conf` | pihole local DNS overrides for the three `funky*.duckdns.org` names |

### `.env` variables

| Variable | Value / use |
|---|---|
| `SERVER_DOMAIN` | `evryfunk`, gives the `.lan/.home/.local` names |
| `SERVER_LAN_IP` | LAN IP of the server (pihole port 53, homer bare-host route) |
| `ACME_EMAIL` | Let's Encrypt account email |
| `TRAEFIK_DUCKDNS_DOMAIN` | `funkyevryfunk`, the DuckDNS name used by traefik |
| `DUCKDNS_DOMAIN` | `avaloki`, untouched: used by the `duckdns` updater and `wireguard` |
| `DUCKDNS_TOKEN` | DuckDNS token, also used for the DNS-01 challenge |
| `WG_EASY_ADMIN_USER` / `WG_EASY_ADMIN_PASSWORD` | wg-easy first-start login |

`TRAEFIK_DUCKDNS_DOMAIN` is separate from `DUCKDNS_DOMAIN` on purpose: the `duckdns` updater
container would otherwise overwrite the tailscale IP of `funkyevryfunk` with the public IP.
Make sure `funkyevryfunk` is **not** in its `SUBDOMAINS`.

## How requests flow

- **HTTPS (443):** traefik picks a router by `Host(...)`. Docker-labelled services
  (dashy, glances, wg-easy, the dashboard) use the default rule or an explicit rule. Everything else is
  declared in `dynamic_tls.yml` and proxied to the **published port** of the container through
  `host.docker.internal`.
- **HTTP (80):** the bare host (`evryfunk.lan/.home/.local`, the LAN IP) goes straight to homer, no
  redirect. Every other host hits a priority-1 catch-all router and is redirected to https. This
  replaces the global redirect used on the other machines, so that `http://evryfunk.lan` keeps working.
- **Wildcard certificate:** requested once by the `traefik-dashboard` router with the DuckDNS
  DNS-01 challenge. It only needs outbound access, no port has to be reachable from the internet.
  The first issuance waits about 2 minutes.

## Remote services (brownfunk)

These replace the old `portforward_*` containers. Traefik proxies to `brownfunk.lan` (resolved
through the pihole container).

| Service | HTTPS name | Plain-http port on evryfunk | Backend |
|---|---|---|---|
| radarr (fr) | `radarr-fr.<domain>` | `evryfunk.lan:7879` | `brownfunk.lan:7879` |
| calibre | `calibre.<domain>` | `evryfunk.lan:8081` | `brownfunk.lan:8081` |
| navidrome | `navidrome.<domain>` | `evryfunk.lan:8082` | `brownfunk.lan:8082` |
| calibre-web | `calibre-web.<domain>` | `evryfunk.lan:8083` | `brownfunk.lan:8083` |
| shelfmark | `shelfmark.<domain>` | none (https only) | `brownfunk.lan:8084` |

The `evryfunk.lan:<port>` entry only needs DNS for `evryfunk.lan` (or use the LAN IP). The client
never has to reach `brownfunk.lan`.

## Local services

Reachable as `https://<name>.funkyevryfunk.duckdns.org` (and `.evryfunk.lan/.home/.local`), direct
ports unchanged.

| Name | Port | | Name | Port |
|---|---|---|---|---|
| jellyfin | 8096 | | prowlarr | 9696 |
| nextcloud | 9393 (https) | | jackett | 9117 |
| immich | 2283 | | transmission | 9091 |
| immich-kiosk | 3000 | | pihole | 455 (`/admin`) |
| mealie | 9925 | | keeweb | 8877 |
| lingodiary | 8084 | | aerofoil | 8465 |
| tandoor | 1141 | | filebrowser | 9295 |
| scrutiny | 8033 | | firefox | 3008 |
| copyparty | 3923 | | | |

Labelled containers: `dashy`, `glances`, `wg-easy` (web UI only through traefik), and `homer`
(bare host, plain http, direct port moved from 80 to **8080**).

## Ports used on the host

| Port | Service |
|---|---|
| 80, 443 | traefik |
| 7879, 8081, 8082, 8083 | traefik plain-http entrypoints (brownfunk services) |
| 8080 | homer (was 80) |
| 53 on `100.65.194.124` and `$SERVER_LAN_IP` (tcp+udp), 5353 | pihole DNS |
| 455 | pihole web |
| 51820/udp | `wireguard` (linuxserver) |
| 51821/udp | `wg-easy` WireGuard (the web UI on 51821/tcp is not published) |

## Pihole

- Port 53 is published on the tailscale IP and on `$SERVER_LAN_IP`, so it can be the DNS server
  of the router / TP-Link Deco (DHCP DNS) as well as of tailscale clients.
- `pihole/etc-dnsmasq.d/02-custom.conf` is mounted as the whole `/etc/dnsmasq.d` directory
  (`FTLCONF_misc_etc_dnsmasq_d=true`). It makes `*.funkyevryfunk.duckdns.org` resolve to the **LAN IP**
  (lower latency) for pihole users, and the beefunk/brownfunk names to their tailscale IPs.
  The LAN IP is hardcoded there: update it if `SERVER_LAN_IP` changes.
- `pihole.toml` is **not** tracked or mounted: pihole rewrites it and it contains the web password
  hash. The non-default settings (upstreams, `dns.hosts`, interface, web port) are `FTLCONF_*`
  environment variables of the `pihole_v6` service instead. They show as read-only in the web UI,
  change them in `docker-compose.yml`.
- If pihole is the only DNS server of a client and evryfunk is down, that client has no DNS.
  Prefer a secondary DNS that is not a public resolver (it would answer with the unreachable
  tailscale IP for `funkyevryfunk`).

## wg-easy

`ghcr.io/wg-easy/wg-easy:15`, UI at `https://wg-easy.funkyevryfunk.duckdns.org`. WireGuard listens
on **51821/udp** because 51820/udp is used by the existing `wireguard` service. Forward 51821/udp
on the router to `SERVER_LAN_IP`. Init settings (admin, host, DNS, allowed IPs) only apply on the
first start of the `wg-easy` volume; change them in the UI afterwards.

## Deploy

```sh
git pull
./fleet decrypt            # .env, acme.json, certs/evryfunk.key
docker compose up -d       # homer moves off port 80 in the same step
docker logs -f traefik     # first certificate issuance takes a few minutes
```

Check:

```sh
curl -I http://evryfunk.lan                                     # 200, homer, no redirect
curl -I http://jellyfin.funkyevryfunk.duckdns.org               # 308 -> https
curl -I https://home.funkyevryfunk.duckdns.org                  # dashy, valid cert
docker exec traefik wget -qO- http://brownfunk.lan:8083 | head  # traefik reaches brownfunk
```

## Troubleshooting

- **Certificate not issued:** `docker logs traefik | grep -i acme`. Check `DUCKDNS_TOKEN` and that
  `acme.json` is mode 600. Self-signed names keep working meanwhile.
- **404 from traefik:** the host name matches no router. Check the exact name against
  `traefik/dynamic_tls.yml` or the container labels.
- **502 from traefik:** the backend port is down, or (remote services) traefik cannot resolve
  `brownfunk.lan` through pihole.
- **Browser warning on `*.evryfunk.lan`:** expected, self-signed. Use the `duckdns.org` names for a valid certificate.
- **Names do not resolve:** the client is not on the tailnet and does not use pihole as DNS.
