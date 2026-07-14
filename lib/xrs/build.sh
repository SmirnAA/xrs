# xrs shared library — VLESS URI parsing and xray config generation.
#
# Source this file, then call (in order):
#   xrs_parse_uri "<vless://...>"   # populates VL_* globals, returns 1 on bad scheme
#   xrs_validate                    # checks VL_* fields, prints errors, returns 1 if invalid
#   xrs_build_config                # echoes the full xray config.json to stdout
#
# Parsed fields are exposed as globals prefixed VL_ so callers can build previews.

# percent-decode (RFC 3986); leaves '+' alone — it is literal outside forms
xrs_urldecode() {
  printf '%b' "${1//%/\\x}"
}

# shellcheck disable=SC2034  # VL_* are consumed by callers
xrs_parse_uri() {
  local uri="$1" rest hostport fragment query key val pair

  VL_uuid="" VL_address="" VL_port="" VL_name=""
  VL_security="none" VL_network="tcp" VL_fingerprint="chrome"
  VL_sni="" VL_pbk="" VL_sid="" VL_flow=""
  unset VL_params; declare -gA VL_params=()

  [[ "$uri" == vless://* ]] || { echo "not a VLESS URI (must start with vless://)" >&2; return 1; }

  rest="${uri#vless://}"

  # fragment = profile name
  if [[ "$rest" == *"#"* ]]; then
    fragment=$(xrs_urldecode "${rest##*#}")
    rest="${rest%%#*}"
    VL_name="$fragment"
  fi

  # query string
  if [[ "$rest" == *"?"* ]]; then
    query="${rest#*\?}"
    rest="${rest%%\?*}"
  else
    query=""
  fi

  # uuid@host:port
  VL_uuid="${rest%%@*}"
  hostport="${rest#*@}"
  VL_address="${hostport%%:*}"
  VL_port="${hostport##*:}"

  # query params into VL_params
  IFS='&' read -ra pairs <<< "$query"
  for pair in "${pairs[@]}"; do
    [[ -z "$pair" ]] && continue
    key="${pair%%=*}"
    val=$(xrs_urldecode "${pair#*=}")
    VL_params["$key"]="$val"
  done

  VL_security="${VL_params[security]:-none}"
  VL_network="${VL_params[type]:-tcp}"
  VL_fingerprint="${VL_params[fp]:-chrome}"
  VL_sni="${VL_params[sni]:-}"
  VL_pbk="${VL_params[pbk]:-}"
  VL_sid="${VL_params[sid]:-}"
  VL_flow="${VL_params[flow]:-}"
  return 0
}

xrs_validate() {
  local -a errors=()
  local uuid_re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

  [[ "$VL_uuid" =~ $uuid_re ]] || errors+=("invalid UUID: $VL_uuid")
  [[ -z "$VL_address" ]] && errors+=("address is empty")

  if [[ "$VL_port" =~ ^[0-9]+$ ]] && (( VL_port >= 1 && VL_port <= 65535 )); then :; else
    errors+=("invalid port: $VL_port")
  fi

  if [[ "$VL_security" == "reality" ]]; then
    [[ -z "$VL_pbk" ]] && errors+=("reality requires pbk (public key)")
    [[ -z "$VL_sni" ]] && errors+=("reality requires sni (server name)")
  fi

  if (( ${#errors[@]} > 0 )); then
    for e in "${errors[@]}"; do echo "  • $e" >&2; done
    return 1
  fi
  return 0
}

# sanitize an arbitrary string into a safe profile-name component
# Allowed: [a-z0-9_-] plus any non-ASCII char (emoji, accented/CJK/Cyrillic
# letters, …); every other ASCII char becomes '_'. The brackets below only
# match ASCII bytes, so multi-byte UTF-8 sequences (all bytes >= 0x80) pass
# through untouched regardless of locale.
#
# Flag emoji for Germany/Russia/USA/Armenia/France are first rewritten to
# their ASCII country codes (de/ru/us/am/fr) so subscription names carry
# readable labels instead of the raw regional-indicator pairs.
xrs_sanitize_name() {
  local n="$1"
  n="${n//$'\U0001F1E9\U0001F1EA'/de}"   # 🇩🇪 -> de
  n="${n//$'\U0001F1F7\U0001F1FA'/ru}"   # 🇷🇺 -> ru
  n="${n//$'\U0001F1FA\U0001F1F8'/us}"   # 🇺🇸 -> us
  n="${n//$'\U0001F1E6\U0001F1F2'/am}"   # 🇦🇲 -> am
  n="${n//$'\U0001F1EB\U0001F1F7'/fr}"   # 🇫🇷 -> fr
  n="${n,,}"                             # lowercase ASCII
  n="${n//[[:cntrl:]]/_}"                # control chars -> _
  local bad=' !"#$%&'\''()*+,./:;<=>?@[\]^`{|}~'  # unsafe ASCII punctuation/space
  n="${n//[$bad]/_}"                     # rest -> _, keeping a-z 0-9 _ - and Unicode
  printf '%s' "$n"
}

xrs_build_config() {
  command -v jq >/dev/null || { echo "jq is required (sudo apt install jq)" >&2; return 1; }

  local user_json stream_json

  user_json=$(jq -n --arg id "$VL_uuid" --arg flow "$VL_flow" \
    'if $flow == "" then {id:$id,encryption:"none"} else {id:$id,encryption:"none",flow:$flow} end')

  stream_json=$(jq -n --arg net "$VL_network" '{network:$net}')

  if [[ "$VL_security" == "reality" ]]; then
    stream_json=$(echo "$stream_json" | jq \
      --arg sni "$VL_sni" --arg pbk "$VL_pbk" --arg sid "$VL_sid" --arg fp "$VL_fingerprint" \
      '. + {security:"reality",realitySettings:{serverName:$sni,publicKey:$pbk,shortId:$sid,fingerprint:$fp}}')
  elif [[ "$VL_security" == "tls" ]]; then
    stream_json=$(echo "$stream_json" | jq \
      --arg sni "$VL_sni" --arg fp "$VL_fingerprint" \
      '. + {security:"tls",tlsSettings:{serverName:$sni,fingerprint:$fp}}')
  fi

  if [[ "$VL_network" == "ws" ]]; then
    local ws_host="${VL_params[host]:-$VL_sni}" ws_path="${VL_params[path]:-/}"
    stream_json=$(echo "$stream_json" | jq \
      --arg path "$ws_path" --arg host "$ws_host" \
      '. + {wsSettings:{path:$path,headers:{Host:$host}}}')
  fi

  if [[ "$VL_network" == "grpc" ]]; then
    local svc="${VL_params[serviceName]:-}"
    stream_json=$(echo "$stream_json" | jq --arg svc "$svc" '. + {grpcSettings:{serviceName:$svc}}')
  fi

  if [[ "$VL_network" == "xhttp" ]]; then
    local xh_path="${VL_params[path]:-/}" xh_host="${VL_params[host]:-}"
    local xh_mode="${VL_params[mode]:-auto}" xh_extra="${VL_params[extra]:-}"
    stream_json=$(echo "$stream_json" | jq \
      --arg path "$xh_path" --arg host "$xh_host" --arg mode "$xh_mode" \
      '. + {xhttpSettings:({path:$path,mode:$mode} + (if $host != "" then {host:$host} else {} end))}')
    # 'extra' is a JSON blob; some panels form-encode it, turning spaces into '+'
    if [[ -n "$xh_extra" ]]; then
      if ! printf '%s' "$xh_extra" | jq -e . >/dev/null 2>&1; then
        xh_extra="${xh_extra//+/ }"
      fi
      if printf '%s' "$xh_extra" | jq -e . >/dev/null 2>&1; then
        stream_json=$(echo "$stream_json" | jq --argjson extra "$xh_extra" '.xhttpSettings.extra = $extra')
      fi
    fi
  fi

  # TCP keepalive on the proxy outbound: XTLS-Vision opens one TCP per stream
  # (no mux), and relay/NAT hops silently black-hole idle flows without a RST.
  # Without keepalive those dead sockets pile up and get reused → requests hang
  # until the app times out. SO_KEEPALIVE lets the OS detect and drop them fast.
  stream_json=$(echo "$stream_json" | jq \
    '. + {sockopt:{tcpKeepAliveIdle:30,tcpKeepAliveInterval:15}}')

  jq -n \
    --arg addr "$VL_address" \
    --argjson port "$VL_port" \
    --argjson user "$user_json" \
    --argjson stream "$stream_json" \
  '{
    log: {loglevel:"warning"},
    policy: {levels:{"0":{handshake:4,connIdle:120,uplinkOnly:1,downlinkOnly:1}}},
    dns: {servers:["1.1.1.1","8.8.8.8"],queryStrategy:"UseIP"},
    inbounds: [
      {tag:"socks-in",listen:"127.0.0.1",port:10808,protocol:"socks",settings:{udp:true,auth:"noauth"},sniffing:{enabled:true,destOverride:["http","tls"]}},
      {tag:"http-in",listen:"127.0.0.1",port:10809,protocol:"http",sniffing:{enabled:true,destOverride:["http","tls"]}}
    ],
    outbounds: [
      {tag:"proxy",protocol:"vless",settings:{vnext:[{address:$addr,port:$port,users:[$user]}]},streamSettings:$stream},
      {tag:"direct",protocol:"freedom",settings:{domainStrategy:"UseIP"}},
      {tag:"block",protocol:"blackhole"}
    ],
    routing: {
      domainStrategy:"IPIfNonMatch",
      rules: [
        {type:"field",ip:["geoip:private"],outboundTag:"direct"},
        {type:"field",domain:["geosite:category-ru","geosite:ru-available-only-inside","regexp:.*\\.ru$"],outboundTag:"direct"},
        {type:"field",ip:["geoip:ru"],outboundTag:"direct"},
        {type:"field",network:"tcp,udp",outboundTag:"proxy"}
      ]
    }
  }'
}
