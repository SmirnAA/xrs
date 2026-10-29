#!/usr/bin/env bash
# Self-check for lib/xrs/build.sh: URI parsing, validation, name sanitizing and
# config generation. Needs only bash and jq. Run: tests/test_build.sh
set -euo pipefail
# shellcheck source=../lib/xrs/build.sh
source "$(dirname "$0")/../lib/xrs/build.sh"

fail=0
check() {  # description expected actual
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; fail=1; fi
}

uuid=11111111-2222-3333-4444-555555555555

xrs_parse_uri "vless://$uuid@example.com:443?security=reality&pbk=KEY&sni=www.example.com&sid=ab&flow=xtls-rprx-vision#%F0%9F%87%A9%F0%9F%87%AA%20Berlin"
check "uuid"     "$uuid"            "$VL_uuid"
check "address"  "example.com"      "$VL_address"
check "port"     "443"              "$VL_port"
check "sni"      "www.example.com"  "$VL_sni"
check "fragment decoded" $'\U0001F1E9\U0001F1EA Berlin' "$VL_name"
check "flag -> country code" "de_berlin" "$(xrs_sanitize_name "$VL_name")"
xrs_validate && check "valid reality uri" 0 0

cfg=$(xrs_build_config)
check "reality publicKey" "KEY"   "$(jq -r '.outbounds[0].streamSettings.realitySettings.publicKey' <<<"$cfg")"
check "no mux for reality" "null" "$(jq -c '.outbounds[0].mux' <<<"$cfg")"
check "no finalmask without fm" "null" "$(jq -c '.outbounds[0].streamSettings.finalmask' <<<"$cfg")"

fm='%7B%22tcp%22%3A%5B%7B%22type%22%3A%22fragment%22%2C%22settings%22%3A%7B%22length%22%3A%22100-200%22%2C%22packets%22%3A%22tlshello%22%2C%22interval%22%3A%220-1%22%7D%7D%5D%7D'
xrs_parse_uri "vless://$uuid@example.com:443?security=reality&pbk=KEY&sni=www.example.com&sid=ab&fm=$fm#x"
cfg=$(xrs_build_config)
check "fm -> finalmask" "tlshello" "$(jq -r '.outbounds[0].streamSettings.finalmask.tcp[0].settings.packets' <<<"$cfg")"
xrs_parse_uri "vless://$uuid@example.com:443?security=reality&pbk=KEY&sni=www.example.com&sid=ab&fm=garbage#x"
check "bad fm ignored" "null" "$(xrs_build_config | jq -c '.outbounds[0].streamSettings.finalmask')"

xrs_parse_uri "vless://$uuid@example.com:8443?security=tls&type=ws&path=%2Fws&sni=cdn.example.com"
cfg=$(xrs_build_config)
check "ws path"   "/ws" "$(jq -r '.outbounds[0].streamSettings.wsSettings.path' <<<"$cfg")"
check "mux on ws" "true" "$(jq -r '.outbounds[0].mux.enabled' <<<"$cfg")"

xrs_parse_uri "vless://not-a-uuid@example.com:99999?security=reality"
xrs_validate 2>/dev/null && check "rejects bad uri" 1 0 || check "rejects bad uri" 1 1
xrs_parse_uri "vmess://x" 2>/dev/null && check "rejects non-vless" 1 0 || check "rejects non-vless" 1 1

check "unsafe chars" "a_b_c_ü" "$(xrs_sanitize_name 'A/b c:ü')"

exit "$fail"
