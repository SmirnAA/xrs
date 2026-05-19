#!/usr/bin/env bash
set -euo pipefail

SCRIPTS=(xrs xrs-add xrs-rm xrs-status xrs-update-geo)
DEST="/usr/local/bin"
PROFILES_DIR="/etc/xray/profiles"
CONFIG_DIR="/usr/local/etc/xray"

for s in "${SCRIPTS[@]}"; do
  cp "bin/$s" "$DEST/$s"
  chmod 755 "$DEST/$s"
  echo "installed $DEST/$s"
done

mkdir -p "$PROFILES_DIR"
mkdir -p "$CONFIG_DIR"

cp completions/xrs.bash /etc/bash_completion.d/xrs
echo "installed /etc/bash_completion.d/xrs"

echo "done"
