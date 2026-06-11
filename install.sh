#!/usr/bin/env bash
set -euo pipefail

SCRIPTS=(xrs xrs-add xrs-rm xrs-sub xrs-status xrs-update-geo)
DEST="/usr/local/bin"
LIB_DIR="/usr/local/lib/xrs"
PROFILES_DIR="/etc/xray/profiles"
SUBS_DIR="/etc/xray/subscriptions"
CONFIG_DIR="/usr/local/etc/xray"

for s in "${SCRIPTS[@]}"; do
  cp "bin/$s" "$DEST/$s"
  chmod 755 "$DEST/$s"
  echo "installed $DEST/$s"
done

mkdir -p "$LIB_DIR"
cp lib/xrs/build.sh "$LIB_DIR/build.sh"
chmod 644 "$LIB_DIR/build.sh"
echo "installed $LIB_DIR/build.sh"

mkdir -p "$PROFILES_DIR"
mkdir -p "$SUBS_DIR"
mkdir -p "$CONFIG_DIR"

cp completions/xrs.bash /etc/bash_completion.d/xrs
echo "installed /etc/bash_completion.d/xrs"

echo "done"
