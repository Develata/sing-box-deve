#!/usr/bin/env bash

sbd_host_file_record() {
  local path="$1" id
  [[ "$path" == /* && "$path" != *$'\n'* && "$path" != *'|'* ]] || return 2
  id="$(printf '%s' "$path" | sha256sum)" || return 1
  printf '%s/ownership/%s\n' "$(sbd_host_state_dir)" "${id%% *}"
}

# Write-ahead baseline. Existing resources are preserved as original content.
sbd_host_file_prepare() {
  local path="$1" record stage
  record="$(sbd_host_file_record "$path")" || return 1
  [[ ! -L "$path" && ! -L "$record" ]] || return 1
  if [[ -f "$record/path" ]]; then
    [[ -f "$record/before" || -f "$record/absent" ]] || return 1
    [[ -e "$path" || -L "$path" ]] || return 0
    sbd_host_file_unchanged "$path" || { log_error "Managed file changed or incomplete: ${path}"; return 1; }
    return 0
  fi
  [[ ! -e "$record" ]] || return 1
  (umask 077; mkdir -p "$(dirname "$record")") || return 1
  stage="$(mktemp -d "${record}.prepare.XXXXXX")" || return 1
  if [[ -f "$path" ]]; then
    cp -p "$path" "$stage/before" || return 1
    cmp -s "$path" "$stage/before" || return 1
  elif [[ ! -e "$path" ]]; then
    : > "$stage/absent" || return 1
  else
    return 1
  fi
  printf '%s\n' "$path" > "$stage/path" || return 1
  mv -T "$stage" "$record"
}

# Record both undo and expected content before publishing a host file.
sbd_host_file_publish() {
  local path="$1" candidate="$2" record journal="" hash pending
  [[ -f "$candidate" && ! -L "$candidate" ]] || return 1
  record="$(sbd_host_file_record "$path")" || return 1
  if grep -q '^# Managed by sing-box-deve: service-v1$' "$candidate" && [[ -e "$path" || -L "$path" ]]; then
    sbd_managed_unit_file "$path" || { log_error "Refusing to replace a service with unproven ownership: $path"; return 1; }
  fi
  if [[ -n "${SBD_ACTIVE_TRANSACTION:-}" ]]; then
    journal="$SBD_ACTIVE_TRANSACTION/host/$(basename "$record")"
    if [[ ! -e "$journal" ]]; then
      (umask 077; mkdir -p "$journal") || return 1
      printf '%s\n' "$path" > "$journal/path" || return 1
      if [[ -f "$path" && ! -L "$path" ]]; then cp -p "$path" "$journal/before" || return 1
      elif [[ ! -e "$path" && ! -L "$path" ]]; then : > "$journal/absent" || return 1
      else return 1; fi
      if [[ -d "$record" ]]; then cp -a "$record" "$journal/ledger" || return 1; fi
    fi
    hash="$(sha256sum "$candidate")" || return 1
    # Keep every published/in-flight digest: interruption before a later rename
    # must still recognize the earlier bytes written by this transaction.
    pending="$(mktemp "$journal/expected.XXXXXX")" || return 1
    if [[ -f "$journal/expected" ]]; then cat "$journal/expected" > "$pending" || return 1; fi
    printf '%s\n' "${hash%% *}" >> "$pending" || return 1
    mv -f "$pending" "$journal/expected" || return 1
    sbd_sync_directory "$journal" || return 1
  fi
  sbd_host_file_prepare "$path" || return 1
  mv -f "$candidate" "$path" || return 1
  sbd_host_file_commit "$path"
}

sbd_host_transaction_restore() {
  local dir="$1" journal path hash record tmp
  [[ -d "$dir/host" ]] || return 0
  for journal in "$dir/host"/*; do
    [[ -d "$journal" && ! -L "$journal" ]] || return 1
    IFS= read -r path < "$journal/path" || return 1
    record="$(sbd_host_file_record "$path")" || return 1
    [[ "$(basename "$record")" == "$(basename "$journal")" && ! -L "$path" ]] || return 1
    if [[ -f "$journal/before" ]] && cmp -s "$path" "$journal/before"; then :
    elif [[ -f "$journal/absent" && ! -e "$path" ]]; then :
    else
      [[ -f "$path" && -f "$journal/expected" ]] || return 1
      hash="$(sha256sum "$path")" || return 1
      grep -Fxq -- "${hash%% *}" "$journal/expected" || { log_error "Host resource changed during recovery: $path"; return 1; }
      if [[ -f "$journal/before" ]]; then
        tmp="$(mktemp "${path}.recover.XXXXXX")" || return 1
        cp -p "$journal/before" "$tmp" && mv -f "$tmp" "$path" || return 1
      elif [[ -f "$journal/absent" ]]; then rm -f -- "$path" || return 1
      else return 1; fi
    fi
    rm -rf -- "$record" || return 1
    [[ ! -d "$journal/ledger" ]] || cp -a "$journal/ledger" "$record" || return 1
  done
}

sbd_host_file_commit() {
  local path="$1" record sum tmp
  record="$(sbd_host_file_record "$path")" || return 1
  [[ -f "$record/path" && -f "$path" && ! -L "$path" ]] || return 1
  sum="$(sha256sum "$path")" || return 1
  tmp="$(mktemp "$record/after.XXXXXX")" || return 1
  printf '%s\n' "${sum%% *}" > "$tmp" || return 1
  mv -f "$tmp" "$record/after.sha256"
}

sbd_host_file_unchanged() {
  local path="$1" record sum
  record="$(sbd_host_file_record "$path")" || return 1
  [[ -f "$record/after.sha256" && -f "$path" && ! -L "$path" ]] || return 1
  sum="$(sha256sum "$path")" || return 1
  [[ "${sum%% *}" == "$(<"$record/after.sha256")" ]]
}

sbd_host_purge() {
  local root record path tmp failed=0
  root="$(sbd_host_state_dir)/ownership"
  [[ -d "$root" ]] || return 0
  for record in "$root"/*; do
    [[ -f "$record/path" ]] || continue
    IFS= read -r path < "$record/path" || return 1
    if ! sbd_host_file_unchanged "$path"; then
      log_warn "Keeping changed/unverified host resource: ${path}"
      failed=1
      continue
    fi
    if [[ -f "$record/before" ]]; then
      tmp="$(mktemp "${path}.restore.XXXXXX")" || return 1
      cp -p "$record/before" "$tmp" || return 1
      mv -f "$tmp" "$path" || return 1
    elif [[ -f "$record/absent" ]]; then
      rm -f -- "$path" || return 1
    else
      return 1
    fi
    rm -rf -- "$record" || return 1
    log_info "Reverted verified managed host file: ${path}"
  done
  (( failed == 0 )) || log_warn "Some host resources were preserved; see ownership records"
  # A shared package or ACME home is deliberately not inferred to be unused.
  return 0
}

sbd_host_forget_file() {
  local record
  record="$(sbd_host_file_record "$1")" || return 1
  [[ ! -L "$record" ]] || return 1
  rm -rf -- "$record"
}
