#!/usr/bin/env bash

sbd_runtime_keys() {
  printf '%s\n' runtime_schema state_sha256 provider profile engine protocols argo_mode argo_domain argo_token argo_cdn_endpoints warp_mode route_mode ip_preference cdn_template_host tls_mode acme_cert_path acme_key_path acme_domain acme_email acme_dns_provider web_front_mode web_front_engine web_front_conf web_front_domain hy2_obfs_mode hy2_obfs_password reality_server_name reality_fingerprint reality_handshake_port tls_server_name archive_site_dir vmess_ws_path vless_ws_path vless_xhttp_path vless_xhttp_mode xray_vless_enc xray_xhttp_reality cdn_host_vmess cdn_host_vless_ws cdn_host_vless_xhttp proxyip_vmess proxyip_vless_ws proxyip_vless_xhttp domain_split_direct domain_split_proxy domain_split_block outbound_proxy_link outbound_proxy_mode outbound_proxy_udp_mode outbound_proxy_host outbound_proxy_port outbound_proxy_user outbound_proxy_pass script_root installed_at
}

sbd_validate_runtime_values() {
  local -n values_ref="$1"
  local name allowed
  allowed=" $(sbd_runtime_keys | tr '\n' ' ')"
  for name in "${!values_ref[@]}"; do
    [[ "$allowed" == *" $name "* ]] || { log_error "Unknown runtime key: $name"; return 1; }
  done
  case "${values_ref[provider]:-}" in vps|serv00) ;; *) return 1 ;; esac
  case "${values_ref[profile]:-}" in lite|full) ;; *) return 1 ;; esac
  case "${values_ref[engine]:-}" in sing-box|xray) ;; *) return 1 ;; esac
  [[ -n "${values_ref[protocols]:-}" ]] || return 1
  local -a protocols_list
  IFS=, read -r -a protocols_list <<< "${values_ref[protocols]}"
  for name in "${protocols_list[@]}"; do
    case "$name" in vless-reality|vless-ws|vless-xhttp|shadowsocks-2022|naive|hysteria2|tuic) ;; *) return 1 ;; esac
  done
  case "${values_ref[argo_mode]:-off}" in off|temp|fixed) ;; *) return 1 ;; esac
  case "${values_ref[tls_mode]:-self-signed}" in self-signed|acme|acme-auto) ;; *) return 1 ;; esac
  case "${values_ref[outbound_proxy_udp_mode]:-proxy}" in proxy|direct|block) ;; *) return 1 ;; esac
  [[ -z "${values_ref[script_root]:-}" || "${values_ref[script_root]}" == /* ]] || return 1
}

# V2 files have an end-to-end checksum. Legacy files migrate on their next write.
sbd_verify_runtime_file() {
  local file="$1" expected actual
  [[ -f "$file" && ! -L "$file" ]] || return 1
  if grep -Eq '^[[:space:]]*(export[[:space:]]+)?(runtime_schema|state_sha256)[[:space:]]*=' "$file"; then
    [[ "$(head -n1 "$file")" == 'runtime_schema="2"' ]] || return 1
    expected="$(tail -n1 "$file")"
    [[ "$expected" =~ ^state_sha256=([a-f0-9]{64})$ ]] || { log_error "Incomplete runtime state"; return 1; }
    expected="${BASH_REMATCH[1]}"
    actual="$(head -n -1 "$file" | sha256sum)" || return 1
    [[ "${actual%% *}" == "$expected" ]] || { log_error "Runtime state checksum mismatch"; return 1; }
  fi
}

sbd_seal_runtime_file() {
  local file="$1" tmp hash
  tmp="$(mktemp "${file}.seal.XXXXXX")" || return 1
  {
    printf 'runtime_schema="2"\n'
    sed '/^runtime_schema=/d; /^state_sha256=/d' "$file"
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  hash="$(sha256sum "$tmp")" || { rm -f "$tmp"; return 1; }
  printf 'state_sha256=%s\n' "${hash%% *}" >> "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$file"
}
