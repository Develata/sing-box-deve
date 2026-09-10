#!/usr/bin/env bash

# A versioned, closed inventory: generated configs preserve primary port values;
# identity and sidecar inputs must be restored before any rebuild.
sbd_state_inventory() {
  local name schema="${2:-3}"
  for name in runtime.env config.yaml config.json xray-config.json settings.conf warp-socks5.json clash_custom_rules.list serv00.env serv00-run.sh; do printf 'config|%s\n' "$name"; done
  for name in uuid reality_private.key reality_public.key reality_short_id xray_private.key xray_public.key xray_short_id \
    xray_vless_decryption.key xray_vless_encryption.key ss2022_password hy2_obfs_password cert.pem private.key acme-cert.pem acme-key.pem \
    argo-token argo-exec argo_token argo_mode argo_domain warp-account.env warp-client-id warp-socks5-port \
    cloudflared.sha256 web_front.env archive_site.env archive_site_owner engine-version; do printf 'data|%s\n' "$name"; done
  printf '%s\n' 'state|multi-ports.db' 'state|firewall-rules.db' 'state|context.env'
  printf '%s\n' 'service|core' 'service|argo' 'service|firewall' 'service|warp'
  if [[ "${1:-false}" == true ]]; then
    printf '%s\n' 'bin|sing-box' 'bin|xray' 'bin|cloudflared'
    [[ "$schema" == 2 ]] || printf '%s\n' 'bin|libcronet.so'
  elif [[ "${1:-false}" == sidecars ]]; then
    printf '%s\n' 'bin|cloudflared'
  fi
}

sbd_state_path() {
  local scope="$1" name="$2"
  case "$scope" in
    config) printf '%s/%s\n' "$SBD_CONFIG_DIR" "$name" ;;
    data) printf '%s/%s\n' "$SBD_DATA_DIR" "$name" ;;
    state) printf '%s/%s\n' "$SBD_STATE_DIR" "$name" ;;
    bin) printf '%s/%s\n' "$SBD_BIN_DIR" "$name" ;;
    service)
      case "$name" in
        core) printf '%s\n' "$SBD_SERVICE_FILE" ;;
        argo) printf '%s\n' "$SBD_ARGO_SERVICE_FILE" ;;
        warp) printf '%s\n' "${SBD_WARP_SOCKS_SERVICE_FILE}" ;;
        firewall) printf '%s\n' "$SBD_FW_REPLAY_SERVICE_FILE" ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

sbd_state_capture() {
  local dir="$1" binaries="${2:-false}" scope name path
  [[ ! -e "$dir" && ! -L "$dir" ]] || return 1
  (umask 077; mkdir -p "$dir/files") || return 1
  sbd_state_inventory "$binaries" > "$dir/inventory" || return 1
  while IFS='|' read -r scope name; do
    path="$(sbd_state_path "$scope" "$name")" || return 1
    [[ ! -L "$path" ]] || { log_error "Refusing to snapshot symlink: ${path}"; return 1; }
    mkdir -p "$dir/files/$scope" || return 1
    if [[ -f "$path" ]]; then
      cp -p "$path" "$dir/files/$scope/$name" || return 1
    elif [[ ! -e "$path" ]]; then
      : > "$dir/files/$scope/$name.absent" || return 1
    else
      log_error "Unexpected state object: ${path}"; return 1
    fi
  done < "$dir/inventory"
  printf '3\n' > "$dir/schema" || return 1
  printf '%s\n' "$binaries" > "$dir/includes-binaries" || return 1
  (cd "$dir"; find files -type f -exec sha256sum {} + > checksums.txt) || return 1
  sbd_state_verify "$dir"
}

sbd_state_verify() {
  local dir="$1" binaries expected actual scope name file sum checks="" schema
  [[ -f "$dir/schema" && -s "$dir/checksums.txt" ]] || {
    log_error "Snapshot lacks a complete state inventory: ${dir}"; return 1;
  }
  schema="$(<"$dir/schema")"
  [[ "$schema" == 2 || "$schema" == 3 ]] || return 1
  [[ -z "$(find "$dir" -type l -print -quit)" ]] || return 1
  binaries="$(<"$dir/includes-binaries")"
  [[ "$binaries" == true || "$binaries" == false || "$binaries" == sidecars ]] || return 1
  expected="$(sbd_state_inventory "$binaries" "$schema")"; actual="$(cat "$dir/inventory")" || return 1
  [[ "$expected" == "$actual" ]] || { log_error "Snapshot inventory mismatch"; return 1; }
  while IFS='|' read -r scope name; do
    if [[ -f "$dir/files/$scope/$name" && ! -e "$dir/files/$scope/$name.absent" ]]; then file="files/$scope/$name"
    elif [[ -f "$dir/files/$scope/$name.absent" && ! -e "$dir/files/$scope/$name" ]]; then file="files/$scope/$name.absent"
    else return 1; fi
    sum="$(sha256sum "$dir/$file")" || return 1
    checks+="${sum%% *}  ${file}"$'\n'
  done < "$dir/inventory"
  expected="$(printf '%s' "$checks" | LC_ALL=C sort)"
  actual="$(LC_ALL=C sort "$dir/checksums.txt")" || return 1
  [[ "$expected" == "$actual" ]] || { log_error "Incomplete or corrupt snapshot checksums"; return 1; }
}

sbd_state_restore() {
  local dir="$1" scope name path tmp record
  sbd_state_verify "$dir" || return 1
  # Validate managed service targets before restoring any config/data inputs.
  while IFS='|' read -r scope name; do
    [[ "$scope" == service ]] || continue
    path="$(sbd_state_path "$scope" "$name")" || return 1
    record="$(sbd_host_file_record "$path")" || return 1
    if [[ -e "$path" && -f "$record/after.sha256" ]]; then
      sbd_host_file_unchanged "$path" || { log_error "Service changed outside management: $path"; return 1; }
    fi
  done < "$dir/inventory"
  while IFS='|' read -r scope name; do
    path="$(sbd_state_path "$scope" "$name")" || return 1
    [[ ! -L "$path" ]] || { log_error "State target became a symlink: ${path}"; return 1; }
    if [[ -f "$dir/files/$scope/$name.absent" ]]; then
      rm -f -- "$path" || return 1
    else
      mkdir -p "$(dirname "$path")" || return 1
      tmp="$(mktemp "${path}.restore.XXXXXX")" || return 1
      cp -p "$dir/files/$scope/$name" "$tmp" || { rm -f "$tmp"; return 1; }
      if [[ "$scope" == service ]]; then
        sbd_host_file_publish "$path" "$tmp" || { rm -f "$tmp"; return 1; }
      else
        mv -f "$tmp" "$path" || { rm -f "$tmp"; return 1; }
      fi
    fi
  done < "$dir/inventory"
}
