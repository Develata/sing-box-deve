#!/usr/bin/env bash

sbd_ensure_openresty_confd_include() {
  local conf_root="$1" test_bin="${2:-}" include_line="    include conf.d/*.conf;"
  local nginx_conf="${conf_root}/nginx.conf" tmp_conf backup_conf=""
  mkdir -p "${conf_root}/conf.d"
  if [[ ! -f "$nginx_conf" ]]; then
    [[ "${SBD_USER_MODE:-false}" == "true" ]] && return 0
    die "OpenResty nginx.conf not found: ${nginx_conf}"
  fi
  backup_conf="${nginx_conf}.sbd.bak.$(date +%s)"
  cp -f "$nginx_conf" "$backup_conf"
  tmp_conf="$(mktemp "${nginx_conf}.tmp.XXXXXX")"
  if ! awk -v include="$include_line" '
    function count_delta(s,   i,c,d) {
      d = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "{") d++
        else if (c == "}") d--
      }
      return d
    }
    BEGIN { in_http = 0; depth = 0; inserted = 0 }
    {
      line = $0
      if (!in_http && line ~ /^[[:space:]]*http[[:space:]]*\{/) {
        in_http = 1
        depth = count_delta(line)
        print line
        if (depth == 0 && !inserted) { print include; inserted = 1; in_http = 0 }
        next
      }
      if (in_http) {
        if (line ~ /include[[:space:]]+conf\.d\/\*\.conf;/) inserted = 1
        d = count_delta(line)
        if ((depth + d) == 0 && line ~ /^[[:space:]]*}/ && !inserted) {
          print include
          inserted = 1
        }
        depth += d
        print line
        if (depth == 0) in_http = 0
        next
      }
      print line
    }
    END { if (!inserted) exit 2 }
  ' "$nginx_conf" > "$tmp_conf"; then
    rm -f "$tmp_conf"
    die "Unable to add conf.d include inside OpenResty http{} block"
  fi
  mv -f "$tmp_conf" "$nginx_conf"
  if [[ -n "$test_bin" ]] && ! "$test_bin" -t >/dev/null; then
    mv -f "$backup_conf" "$nginx_conf"
    die "OpenResty nginx.conf failed syntax test after adding conf.d include"
  fi
}
