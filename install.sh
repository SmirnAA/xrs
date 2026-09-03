#!/usr/bin/env bash
set -euo pipefail

# xrs installer — fully automatic, works two ways:
#
#   one-liner (no clone needed):
#     curl -fsSL https://raw.githubusercontent.com/SmirnAA/xrs/main/install.sh | sudo bash
#
#   from a clone:
#     sudo ./install.sh
#
# Installs missing dependencies (jq, fzf, curl), Xray-core (official XTLS
# script) if absent, routing geo files, and the xrs utilities themselves.

REPO="SmirnAA/xrs"
BRANCH="main"

SCRIPTS=(xrs xrs-add xrs-rm xrs-sub xrs-status xrs-update-geo xrs-tun)
DEST="/usr/local/bin"
LIB_DIR="/usr/local/lib/xrs"
PROFILES_DIR="/etc/xray/profiles"
SUBS_DIR="/etc/xray/subscriptions"
CONFIG_DIR="/usr/local/etc/xray"
GEO_DIR="/usr/local/share/xray"
GEO_URL="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download"
XRAY_INSTALLER="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; N=$'\e[0m'
die()  { echo "${R}✗${N} $*" >&2; exit 1; }
ok()   { echo "${G}✓${N} $*"; }
step() { echo; echo "${Y}==>${N} $*"; }

TMP=""
cleanup() { if [[ -n "$TMP" ]]; then rm -rf "$TMP"; fi; }
trap cleanup EXIT

[[ $EUID -eq 0 ]] || die "must run as root:
    curl -fsSL https://raw.githubusercontent.com/$REPO/$BRANCH/install.sh | sudo bash
  or from a clone:
    sudo ./install.sh"

command -v systemctl >/dev/null || die "systemd is required"

# ── 1. Dependencies ────────────────────────────────────────────────────────
step "checking dependencies"
missing=()
for c in curl jq fzf; do
  command -v "$c" >/dev/null || missing+=("$c")
done
if (( ${#missing[@]} > 0 )); then
  echo "installing: ${missing[*]}"
  if command -v apt-get >/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
  elif command -v dnf >/dev/null;    then dnf install -y "${missing[@]}"
  elif command -v yum >/dev/null;    then yum install -y "${missing[@]}"
  elif command -v pacman >/dev/null; then pacman -Sy --noconfirm "${missing[@]}"
  elif command -v zypper >/dev/null; then zypper --non-interactive install "${missing[@]}"
  elif command -v apk >/dev/null;    then apk add "${missing[@]}"
  else
    die "no supported package manager found — install manually: ${missing[*]}"
  fi
fi
ok "curl, jq, fzf"

# ── 2. Locate xrs sources (local clone, or download when piped) ────────────
SRC=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]:-}" ]]; then
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$src_dir/bin/xrs" ]] && SRC="$src_dir"
fi
if [[ -z "$SRC" ]]; then
  step "downloading xrs sources"
  TMP=$(mktemp -d)
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" \
    | tar -xz -C "$TMP" || die "failed to download https://github.com/$REPO"
  SRC="$TMP/xrs-$BRANCH"
  [[ -f "$SRC/bin/xrs" ]] || die "unexpected archive layout in downloaded sources"
fi

# ── 3. Xray-core ───────────────────────────────────────────────────────────
if command -v xray >/dev/null; then
  ok "xray-core already installed ($(xray version 2>/dev/null | head -1))"
else
  step "installing xray-core (official XTLS script)"
  bash -c "$(curl -fsSL "$XRAY_INSTALLER")" @ install || die "xray-core installation failed"
fi
systemctl enable xray >/dev/null 2>&1 || true

# ── 4. Geo files (runetfreedom — the config needs its extended categories) ─
# Robust fetch: GitHub release downloads are often throttled here, so plain
# curl hangs forever mid-transfer. Abort on stall (speed < 30KB/s for 15s) and
# retry with resume, so a stalled transfer fails/recovers instead of hanging.
geo_fetch() {
  local url="$1" out="$2"
  rm -f "$out"
  curl -fL -C - --connect-timeout 10 --speed-limit 30000 --speed-time 15 \
       --retry 5 --retry-delay 2 --retry-all-errors -o "$out" "$url"
}

step "installing geo files"
mkdir -p "$GEO_DIR"
for f in geoip.dat geosite.dat; do
  geo_fetch "$GEO_URL/$f" "$GEO_DIR/$f.new" || die "failed to download $f"
  size=$(stat -c%s "$GEO_DIR/$f.new")
  (( size > 100000 )) || die "$f looks truncated (${size}B)"
  mv "$GEO_DIR/$f.new" "$GEO_DIR/$f"
  ok "$f ($(du -h "$GEO_DIR/$f" | cut -f1))"
done

# ── 5. xrs itself ──────────────────────────────────────────────────────────
step "installing xrs"
install -d "$DEST"
for s in "${SCRIPTS[@]}"; do
  install -m 755 "$SRC/bin/$s" "$DEST/$s"
  ok "$DEST/$s"
done

install -d "$LIB_DIR"
install -m 644 "$SRC/lib/xrs/build.sh" "$LIB_DIR/build.sh"
ok "$LIB_DIR/build.sh"

install -d "$PROFILES_DIR" "$SUBS_DIR" "$CONFIG_DIR"

# Profiles carry wireguard private keys and uuids, so they must not stay
# world-readable. xray runs as nobody, hence the nogroup ownership; an ACL lets
# the invoking user read them from xrs/xrs-status without sudo.
chgrp nogroup "$PROFILES_DIR" "$SUBS_DIR" 2>/dev/null || true
chgrp nogroup "$PROFILES_DIR"/*.json "$SUBS_DIR"/*.json 2>/dev/null || true
chmod 640 "$PROFILES_DIR"/*.json "$SUBS_DIR"/*.json 2>/dev/null || true
if command -v setfacl >/dev/null && [[ -n "${SUDO_USER:-}" ]]; then
  setfacl -d -m "u:$SUDO_USER:r" -m g:nogroup:r "$PROFILES_DIR" "$SUBS_DIR" || true
  setfacl -m "u:$SUDO_USER:r" "$PROFILES_DIR"/*.json "$SUBS_DIR"/*.json 2>/dev/null || true
fi

install -d /etc/bash_completion.d
install -m 644 "$SRC/completions/xrs.bash" /etc/bash_completion.d/xrs
ok "/etc/bash_completion.d/xrs"

# ── 6. TUN toggle (xrs tun on|off) ─────────────────────────────────────────
step "setting up tun toggle"
install -d /etc/systemd/system/xray.service.d
cat > /etc/systemd/system/xray.service.d/tun.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config $CONFIG_DIR/config.json -config /etc/xray/tun.json
EOF
[[ -f /etc/xray/tun.json ]] || echo '{}' > /etc/xray/tun.json
systemctl daemon-reload
systemctl try-restart xray >/dev/null 2>&1 || true
ok "/etc/xray/tun.json + systemd drop-in"

# ── Done ───────────────────────────────────────────────────────────────────
echo
ok "xrs installed"
echo "
next steps:
  1. add a server:       xrs-add 'vless://...'
     or a subscription:  xrs sub add <url> <name>
  2. pick a profile:     xrs
  3. check everything:   xrs-status

(xray will start once you pick a profile — it has no config until then)"
