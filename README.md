# xrs

A set of bash scripts for managing [Xray-core](https://github.com/XTLS/Xray-core) on Linux. Each server is stored as a separate profile, and switching between them takes a single command via `fzf`. The generated config uses split-routing: Russian traffic goes direct, everything else through the proxy.

## Features

- **Server profiles** — add from VLESS links (`vless://`) and subscriptions (base64 or plaintext).
- **Fast switching** — interactive selection via `fzf` with automatic xray restart.
- **Split-routing out of the box** — `*.ru`, `geoip:ru`, `geosite:category-ru` go direct, everything else through VLESS.
- **Diagnostics** — service status, server reachability, tunnel health, split-routing check, geo files, DNS.
- **Geo-file updates** — with config-compatibility check and automatic rollback.

Supports `reality`, `tls`, and the `tcp` / `ws` / `grpc` transports.

## Requirements

Linux with systemd. Everything else (`jq`, `fzf`, `curl`, Xray-core, geo files) is installed automatically by `install.sh`.

## Installation

One command, no clone needed:

```bash
curl -fsSL https://raw.githubusercontent.com/SmirnAA/xrs/main/install.sh | sudo bash
```

Or from a clone:

```bash
git clone https://github.com/SmirnAA/xrs.git
cd xrs
sudo ./install.sh
```

The installer is idempotent (safe to re-run) and:

- installs missing dependencies (`jq`, `fzf`, `curl`) via the system package manager (apt/dnf/yum/pacman/zypper/apk);
- installs [Xray-core](https://github.com/XTLS/Xray-core) via the official XTLS script if it is not present (systemd service `xray`);
- downloads the routing geo files from [runetfreedom](https://github.com/runetfreedom/russia-v2ray-rules-dat) (~90 MB — required for split-routing);
- copies the utilities to `/usr/local/bin/`, the shared library to `/usr/local/lib/xrs/`, the bash completion file, and creates the directories for profiles and subscriptions.

## Quick start

### 1. Add a server

```bash
xrs-add 'vless://uuid@host:443?security=reality&pbk=...&sni=example.com#finland'
```

Or with no arguments — the script will ask you to paste the link and enter a name:

```bash
xrs-add
```

### 2. Add a subscription

```bash
xrs sub add 'https://example.com/sub/token' netherlands
```

The script downloads the subscription (base64 or plaintext), expands each VLESS server into a separate profile `netherlands:<name>`, and skips links of other protocols (vmess/ss/trojan).

```bash
xrs sub update [name]   # re-sync (all, if no name given)
xrs sub rm [name]       # remove a subscription and its profiles
xrs sub ls              # list subscriptions
```

On update, profiles for servers that disappeared from the subscription are removed (the active one is kept).

### 3. Switch profile

```bash
xrs
```

An interactive `fzf` picker opens. Subscription profiles appear alongside regular ones. After you pick one, xray restarts automatically.

Remove a profile:

```bash
xrs-rm [name]   # without a name — pick via fzf
```

### 4. Check status

```bash
xrs-status
```

Shows: active profile, service state, ports, server reachability, proxy operation, split-routing, geo files, and DNS.

### 5. Update geo files

```bash
sudo xrs-update-geo
```

Downloads fresh `geoip.dat` and `geosite.dat`, verifies they are compatible with the config, and restarts xray. On failure — automatic rollback.

## How it works

After you switch a profile, Xray listens locally on:

| Protocol | Address            |
| -------- | ------------------ |
| SOCKS5   | `127.0.0.1:10808`  |
| HTTP     | `127.0.0.1:10809`  |

Point your browser or system at these addresses. Routing works as a split-tunnel:

- private networks, `geoip:ru`, `geosite:category-ru`, and `*.ru` domains go **direct**;
- all other traffic goes **through the VLESS proxy**.

Routing geo files are sourced from [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat).

## Layout

```
/usr/local/bin/
  xrs              — profile switcher (fzf) + subcommand dispatcher
  xrs-add          — add a VLESS server
  xrs-rm           — remove a profile
  xrs-sub          — manage subscriptions (add/update/rm/ls)
  xrs-status       — diagnostics
  xrs-update-geo   — update geo files

/usr/local/lib/xrs/
  build.sh         — shared logic for parsing VLESS URIs and building the config

/etc/xray/profiles/
  *.json           — profiles (from xrs-add and expanded subscriptions)

/etc/xray/subscriptions/
  *.json           — subscription manifests (url + list of profiles)

/usr/local/etc/xray/
  config.json      — symlink to the active profile
```
