#!/usr/bin/env bash

sbd_rotate_file_backups() {
  local file="$1" keep="${2:-2}" i prev
  [[ "$keep" =~ ^[0-9]+$ ]] || die "Backup keep count must be numeric: ${keep}"
  (( keep >= 1 )) || return 0
  [[ -f "$file" ]] || return 0

  for ((i = keep; i >= 2; i--)); do
    prev=$((i - 1))
    if [[ -f "${file}.bak.${prev}" ]]; then
      mv -f "${file}.bak.${prev}" "${file}.bak.${i}" || return 1
    fi
  done
  cp -p "$file" "${file}.bak.1"
}

sbd_restore_latest_file_backup() {
  local file="$1"
  [[ -f "${file}.bak.1" ]] || return 1
  cp -p "${file}.bak.1" "$file"
}

sbd_commit_file_with_backups() {
  local file="$1" tmp_file="$2" mode="${3:-}"
  [[ -f "$tmp_file" ]] || die "Temporary file missing: ${tmp_file}"
  mkdir -p "$(dirname "$file")" || return 1
  sbd_rotate_file_backups "$file" 2 || return 1
  if [[ -n "$mode" ]]; then
    chmod "$mode" "$tmp_file" || return 1
  fi
  mv -f "$tmp_file" "$file" || return 1
}

sbd_json_string() {
  local input="${1-}"
  if command -v jq >/dev/null 2>&1; then
    jq -Rn --arg v "$input" '$v'
    return $?
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$input"
    return $?
  fi

  input="${input//\\/\\\\}"
  input="${input//\"/\\\"}"
  input="${input//$'\n'/\\n}"
  input="${input//$'\r'/\\r}"
  input="${input//$'\t'/\\t}"
  printf '"%s"\n' "$input"
}

sbd_mask_secret() {
  local value="${1-}" len
  [[ -n "$value" ]] || {
    printf ''
    return 0
  }
  len="${#value}"
  if (( len <= 8 )); then
    printf '***'
  else
    printf '%s...%s' "${value:0:4}" "${value:len-4:4}"
  fi
}

sbd_print_env_file_redacted() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  local raw key value lower_key
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    if [[ "$raw" == *=* && ! "$raw" =~ ^[[:space:]]*# ]]; then
      key="${raw%%=*}"
      value="${raw#*=}"
      lower_key="${key,,}"
      case "$lower_key" in
        *token*|*password*|*pass*|*private_key*|*secret*)
          printf '%s=%s\n' "$key" "$(sbd_mask_secret "$value")"
          ;;
        *)
          printf '%s\n' "$raw"
          ;;
      esac
    else
      printf '%s\n' "$raw"
    fi
  done < "$file"
}

# GNU coreutils is a runtime requirement for mutation/recovery paths.
sbd_sync_directory() {
  sbd_run_deadline "${SBD_SYNC_TIMEOUT:-30}" sync -f "$1"
}

sbd_atomic_symlink() {
  local target="$1" link="$2" tmp
  mkdir -p "$(dirname "$link")" || return 1
  tmp="$(mktemp -d "${link}.switch.XXXXXX")" || return 1
  ln -s "$target" "$tmp/link" || { rmdir "$tmp"; return 1; }
  mv -Tf "$tmp/link" "$link" || { rm -f "$tmp/link"; rmdir "$tmp"; return 1; }
  rmdir "$tmp" || return 1
  sbd_sync_directory "$(dirname "$link")"
}
