#!/usr/bin/env bash

sbd_release_verify() {
  local root="$1" file
  sbd_run_deadline 30 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" verify "$root" || return 1
  while IFS= read -r file; do
    [[ "$file" == *.sh ]] || continue
    bash -n "$root/$file" || return 1
  done < "$root/runtime-files.txt"
  sbd_run_deadline 30 bash "$root/sing-box-deve.sh" --self-test
}

sbd_release_activate_archive() {
  local archive="$1" expected="$2" actual releases stage final id version previous=""
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || { log_error "Expected release SHA256 is required"; return 1; }
  actual="$(sha256sum "$archive")" || return 1
  [[ "${actual%% *}" == "${expected,,}" ]] || { log_error "Release digest mismatch"; return 1; }
  releases="$SBD_INSTALL_DIR/releases"
  [[ ! -L "$releases" ]] || return 1
  mkdir -p "$releases" || return 1
  stage="$(mktemp -d "$releases/.stage.XXXXXX")" || return 1
  if ! sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" extract "$archive" "$stage" || ! sbd_release_verify "$stage"; then
    rm -rf "$stage"
    return 1
  fi
  version="$(tr -d '[:space:]' < "$stage/version")"
  [[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]] || { rm -rf "$stage"; return 1; }
  id="${version}-${expected:0:16}"; final="$releases/$id"
  if [[ -d "$final" && ! -L "$final" ]]; then
    sbd_release_verify "$final" || { rm -rf "$stage"; return 1; }
    diff -q "$stage/checksums.txt" "$final/checksums.txt" >/dev/null || { rm -rf "$stage"; return 1; }
    rm -rf "$stage"
  else
    sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" fsync "$stage" || return 1
    mv -T "$stage" "$final" || return 1
    sbd_sync_directory "$releases" || return 1
  fi
  if [[ -L "$SBD_INSTALL_DIR/current" ]]; then
    previous="$(readlink -f "$SBD_INSTALL_DIR/current")" || return 1
    [[ "$previous" == "$releases/"* && "$previous" != "$final" ]] || previous=""
  fi
  [[ -z "$previous" ]] || sbd_atomic_symlink "$previous" "$SBD_INSTALL_DIR/previous" || return 1
  sbd_atomic_symlink "$final" "$SBD_INSTALL_DIR/current" || return 1
  if ! sbd_release_verify "$final"; then
    [[ -z "$previous" ]] || sbd_atomic_symlink "$previous" "$SBD_INSTALL_DIR/current" || return 1
    return 1
  fi
  if ! write_sb_launcher || ! sbd_update_runtime_script_root "$SBD_INSTALL_DIR/current"; then
    [[ -z "$previous" ]] || sbd_atomic_symlink "$previous" "$SBD_INSTALL_DIR/current" || return 1
    return 1
  fi
  sbd_release_prune || return 1
  log_success "Activated complete script release: ${id}"
}

sbd_release_install_tree() {
  local source_root="$1" tmp sum
  tmp="$(mktemp -d)" || return 1
  if ! sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" pack "$source_root" "$tmp/runtime.tar.gz"; then
    rm -rf "$tmp"; return 1
  fi
  sum="$(sha256sum "$tmp/runtime.tar.gz")" || { rm -rf "$tmp"; return 1; }
  if ! sbd_release_activate_archive "$tmp/runtime.tar.gz" "${sum%% *}"; then rm -rf "$tmp"; return 1; fi
  rm -rf "$tmp"
}

sbd_release_download_update() {
  local url="${SBD_RELEASE_ARCHIVE_URL:-}" digest="${SBD_RELEASE_SHA256:-}" json tmp repo tag
  repo="${SBD_REPO_SLUG:-Develata/sing-box-deve}"
  tag="${SBD_RELEASE_TAG:-latest}"
  if [[ -z "$url" ]]; then
    json="$(fetch_release_metadata "$repo" "$tag")" || {
      log_error "No usable runtime release; publish the release artifact or set a pinned archive URL and SHA256"; return 1;
    }
    url="$(jq -er '.assets[] | select(.name == "sing-box-deve-runtime.tar.gz") | .browser_download_url' <<< "$json")" || return 1
    digest="$(jq -er '.assets[] | select(.name == "sing-box-deve-runtime.tar.gz") | .digest | select(startswith("sha256:"))' <<< "$json")" || return 1
    digest="${digest#sha256:}"
  fi
  [[ "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || { log_error "Pinned release SHA256 missing"; return 1; }
  sbd_release_migrate_legacy || return 1
  tmp="$(mktemp -d)" || return 1
  if ! download_file "$url" "$tmp/runtime.tar.gz" || ! sbd_release_activate_archive "$tmp/runtime.tar.gz" "$digest"; then
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
}

sbd_release_rollback() {
  local previous current
  previous="$(readlink -f "$SBD_INSTALL_DIR/previous")" || return 1
  current="$(readlink -f "$SBD_INSTALL_DIR/current")" || return 1
  [[ "$previous" == "$SBD_INSTALL_DIR/releases/"* && -d "$previous" && "$previous" != "$current" ]] || {
    log_error "No complete previous release available"; return 1;
  }
  sbd_release_verify "$previous" || return 1
  sbd_atomic_symlink "$previous" "$SBD_INSTALL_DIR/current" || return 1
  sbd_update_runtime_script_root "$SBD_INSTALL_DIR/current" || return 1
  write_sb_launcher || return 1
  log_success "Restored complete script release: $(basename "$previous")"
}

# Cold migration preserves the exact local legacy runtime before the first switch.
sbd_release_migrate_legacy() (
  [[ ! -L "$SBD_INSTALL_DIR/current" ]] || return 0
  local legacy tmp sum target stage=""
  legacy="$(sbd_read_runtime_script_root 2>/dev/null || true)"
  [[ -n "$legacy" && -f "$legacy/sing-box-deve.sh" ]] || return 0
  tmp="$(mktemp -d)" || return 1
  trap 'rm -rf "$tmp"; [[ -z "$stage" ]] || rm -rf "$stage"' EXIT
  sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" pack-legacy "$legacy" "$tmp/legacy.tar.gz" || return 1
  sum="$(sha256sum "$tmp/legacy.tar.gz")" || return 1
  target="$SBD_INSTALL_DIR/releases/legacy-${sum:0:16}"
  mkdir -p "$SBD_INSTALL_DIR/releases" || return 1
  if [[ ! -e "$target" ]]; then
    stage="$(mktemp -d "$SBD_INSTALL_DIR/releases/.stage.XXXXXX")" || return 1
    sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" extract "$tmp/legacy.tar.gz" "$stage" || return 1
    sbd_release_verify "$stage" || return 1
    sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" fsync "$stage" || return 1
    mv -T "$stage" "$target" || return 1
    stage=""
  fi
  sbd_release_verify "$target" || return 1
  sbd_run_deadline 60 python3 "$PROJECT_ROOT/scripts/runtime-archive.py" fsync "$target" || return 1
  sbd_atomic_symlink "$target" "$SBD_INSTALL_DIR/current" || return 1
  rm -rf "$tmp"
)

sbd_release_prune() {
  [[ ! -L "$(sbd_host_state_dir)/transactions/active" ]] || return 0
  local root="$SBD_INSTALL_DIR/releases" current previous dir count=0 protected=1 budget keep="${SBD_RELEASE_KEEP:-3}"
  [[ "$keep" =~ ^[1-9][0-9]*$ ]] || return 2
  current="$(readlink -f "$SBD_INSTALL_DIR/current")" || return 1
  previous="$(readlink -f "$SBD_INSTALL_DIR/previous" 2>/dev/null || true)"
  [[ -z "$previous" || "$previous" == "$current" ]] || protected=2
  budget=$((keep - protected)); (( budget >= 0 )) || budget=0
  while IFS= read -r dir; do
    [[ -d "$dir" && ! -L "$dir" ]] || continue
    [[ "$dir" != "$current" && "$dir" != "$previous" && ! -e "$SBD_INSTALL_DIR/release-pins/$(basename "$dir")" ]] || continue
    count=$((count + 1))
    (( count > budget )) || continue
    rm -rf -- "$dir" || return 1
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d ! -name '.stage.*' -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
  # Only called under the mutation lock after activation; no concurrent writer.
  for dir in "$root"/.stage.*; do
    [[ ! -d "$dir" || -L "$dir" ]] || rm -rf -- "$dir" || return 1
  done
}
