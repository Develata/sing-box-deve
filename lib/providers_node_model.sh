#!/usr/bin/env bash

node_model_init() {
  mkdir -p "$(dirname "$SBD_NODE_MODEL_FILE")"
  printf '{"version":1,"nodes":[]}\n' > "$SBD_NODE_MODEL_FILE"
  chmod 0600 "$SBD_NODE_MODEL_FILE" 2>/dev/null || true
}

node_model_append() {
  local node_json="$1" tmp
  jq -e 'type == "object" and (.kind | type == "string") and (.tag | type == "string")' \
    >/dev/null <<< "$node_json" || die "Invalid structured node"
  tmp="${SBD_NODE_MODEL_FILE}.tmp.$$"
  jq --argjson node "$node_json" '.nodes += [$node]' "$SBD_NODE_MODEL_FILE" > "$tmp" || {
    rm -f "$tmp"
    die "Unable to update structured node model"
  }
  chmod 0600 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$SBD_NODE_MODEL_FILE"
}

node_model_add_vless_reality() {
  local uuid="$1" server="$2" port="$3" sni="$4" fp="$5" public_key="$6" short_id="$7"
  node_model_append "$(jq -cn \
    --arg kind vless-reality --arg tag sbd-vless-reality --arg uuid "$uuid" \
    --arg server "$server" --argjson port "$port" --arg sni "$sni" --arg fp "$fp" \
    --arg public_key "$public_key" --arg short_id "$short_id" \
    '{kind:$kind,tag:$tag,uuid:$uuid,server:$server,port:$port,sni:$sni,fingerprint:$fp,public_key:$public_key,short_id:$short_id}')"
}

node_model_add_vless_ws() {
  local uuid="$1" server="$2" port="$3" encryption="$4" path="$5" host="$6" tag="${7:-sbd-vless-ws}"
  local tls_enabled="${8:-false}" sni="${9:-}"
  node_model_append "$(jq -cn \
    --arg kind vless-ws --arg tag "$tag" --arg uuid "$uuid" --arg server "$server" \
    --argjson port "$port" --arg encryption "$encryption" --arg path "$path" --arg host "$host" \
    --argjson tls "$tls_enabled" --arg sni "$sni" \
    '{kind:$kind,tag:$tag,uuid:$uuid,server:$server,port:$port,encryption:$encryption,path:$path,host:$host,tls:$tls,sni:$sni,
      singbox_compatible:($encryption == "none"),clash_compatible:($encryption == "none")}')"
}

node_model_add_vless_xhttp() {
  local uuid="$1" server="$2" port="$3" encryption="$4" sni="$5" fp="$6"
  local public_key="$7" short_id="$8" path="$9" mode="${10}" host="${11}"
  local security=none
  if sbd_xhttp_use_reality; then security=reality; fi
  node_model_append "$(jq -cn \
    --arg kind vless-xhttp --arg tag sbd-vless-xhttp --arg uuid "$uuid" --arg server "$server" \
    --argjson port "$port" --arg encryption "$encryption" --arg sni "$sni" --arg fp "$fp" \
    --arg public_key "$public_key" --arg short_id "$short_id" --arg path "$path" \
    --arg mode "$mode" --arg host "$host" --arg security "$security" \
    '{kind:$kind,tag:$tag,security:$security,uuid:$uuid,server:$server,port:$port,encryption:$encryption,sni:$sni,fingerprint:$fp,public_key:$public_key,short_id:$short_id,path:$path,mode:$mode,host:$host,singbox_compatible:false,clash_compatible:false}')"
}

node_model_add_ss2022() {
  local password="$1" server="$2" port="$3"
  node_model_append "$(jq -cn \
    --arg kind shadowsocks-2022 --arg tag sbd-shadowsocks-2022 --arg password "$password" \
    --arg server "$server" --argjson port "$port" \
    '{kind:$kind,tag:$tag,password:$password,server:$server,port:$port}')"
}

node_model_add_naive() {
  local uuid="$1" server="$2" port="$3" sni="$4" insecure="$5"
  node_model_append "$(jq -cn \
    --arg kind naive --arg tag sbd-naive --arg uuid "$uuid" --arg server "$server" \
    --argjson port "$port" --arg sni "$sni" --argjson insecure "$insecure" \
    '{kind:$kind,tag:$tag,username:$uuid,password:$uuid,server:$server,port:$port,sni:$sni,insecure:$insecure,
      singbox_compatible:($insecure == false),clash_compatible:false}')"
}

node_model_add_hysteria2() {
  local uuid="$1" server="$2" port="$3" sni="$4" insecure="$5" obfs_mode="$6" obfs_password="$7"
  node_model_append "$(jq -cn \
    --arg kind hysteria2 --arg tag sbd-hysteria2 --arg password "$uuid" --arg server "$server" \
    --argjson port "$port" --arg sni "$sni" --argjson insecure "$insecure" \
    --arg obfs_mode "$obfs_mode" --arg obfs_password "$obfs_password" \
    '{kind:$kind,tag:$tag,password:$password,server:$server,port:$port,sni:$sni,insecure:$insecure,obfs_mode:$obfs_mode,obfs_password:$obfs_password}')"
}

node_model_value() {
  local node_json="$1" expression="$2"
  jq -r "$expression // empty" <<< "$node_json"
}

node_model_render_uri_file() {
  local out_file="$1" node kind
  : > "$out_file"
  while IFS= read -r node; do
    kind="$(node_model_value "$node" '.kind')"
    case "$kind" in
      vless-reality)
        node_link_vless_reality \
          "$(node_model_value "$node" '.uuid')" "$(node_model_value "$node" '.server')" \
          "$(node_model_value "$node" '.port')" "$(node_model_value "$node" '.sni')" \
          "$(node_model_value "$node" '.fingerprint')" "$(node_model_value "$node" '.public_key')" \
          "$(node_model_value "$node" '.short_id')" >> "$out_file"
        ;;
      vless-ws)
        node_link_vless_ws \
          "$(node_model_value "$node" '.uuid')" "$(node_model_value "$node" '.server')" \
          "$(node_model_value "$node" '.port')" "$(node_model_value "$node" '.encryption')" \
          "$(uri_encode "$(node_model_value "$node" '.path')")" "$(node_model_value "$node" '.host')" \
          "$(if [[ "$(node_model_value "$node" '.tls')" == "true" ]]; then printf tls; else printf none; fi)" \
          "$(node_model_value "$node" '.sni')" "$(node_model_value "$node" '.tag')" >> "$out_file"
        ;;
      vless-xhttp)
        node_link_vless_xhttp \
          "$(node_model_value "$node" '.uuid')" "$(node_model_value "$node" '.server')" \
          "$(node_model_value "$node" '.port')" "$(node_model_value "$node" '.encryption')" \
          "$(node_model_value "$node" '.sni')" "$(node_model_value "$node" '.fingerprint')" \
          "$(node_model_value "$node" '.public_key')" "$(node_model_value "$node" '.short_id')" \
          "$(uri_encode "$(node_model_value "$node" '.path')")" "$(node_model_value "$node" '.mode')" \
          "$(node_model_value "$node" '.host')" "$(node_model_value "$node" '.security // "reality"')" >> "$out_file"
        ;;
      shadowsocks-2022)
        node_link_ss2022 "$(node_model_value "$node" '.password')" \
          "$(node_model_value "$node" '.server')" "$(node_model_value "$node" '.port')" >> "$out_file"
        ;;
      naive)
        node_link_naive "$(node_model_value "$node" '.username')" \
          "$(node_model_value "$node" '.server')" "$(node_model_value "$node" '.port')" \
          "$(node_model_value "$node" '.sni')" >> "$out_file"
        ;;
      hysteria2)
        node_link_hysteria2 "$(node_model_value "$node" '.password')" \
          "$(node_model_value "$node" '.server')" "$(node_model_value "$node" '.port')" \
          "$(node_model_value "$node" '.sni')" "$(node_model_value "$node" '.obfs_mode')" \
          "$(node_model_value "$node" '.obfs_password')" >> "$out_file"
        ;;
    esac
  done < <(jq -c '.nodes[]' "$SBD_NODE_MODEL_FILE")
}
