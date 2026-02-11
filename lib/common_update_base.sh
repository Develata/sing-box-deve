#!/usr/bin/env bash
# shellcheck disable=SC2034

current_script_version() {
  local version_file="${PROJECT_ROOT}/version"
  if [[ -f "$version_file" ]]; then
    tr -d '[:space:]' < "$version_file"
  else
    echo "v0.0.0-dev"
  fi
}

update_url_with_cache_bust() {
  local url="$1" token="${2:-}"
  [[ -n "$token" ]] || {
    echo "$url"
    return 0
  }
  if [[ "$url" == *\?* ]]; then
    echo "${url}&_cb=${token}"
  else
    echo "${url}?_cb=${token}"
  fi
}

fetch_remote_script_version() {
  local mode="${1:-${UPDATE_SOURCE:-auto}}" base_url version cb version_url
  cb="$(date +%s)"
  while IFS= read -r base_url; do
    [[ -n "$base_url" ]] || continue
    version_url="$(update_url_with_cache_bust "${base_url}/version" "$cb")"
    version="$(curl -fsSL "$version_url" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -n "$version" ]]; then
      SBD_ACTIVE_UPDATE_BASE_URL="$base_url"
      echo "$version"
      return 0
    fi
  done < <(update_base_candidates "$mode")
  return 1
}

is_git_repo() {
  [[ -d "${PROJECT_ROOT}/.git" ]] && command -v git >/dev/null 2>&1
}

get_git_branch() {
  git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

get_git_remote() {
  git -C "$PROJECT_ROOT" config --get remote.origin.url 2>/dev/null || true
}

validate_project_root() {
  if [[ -z "${PROJECT_ROOT:-}" ]]; then
    die "$(msg "PROJECT_ROOT 未设置" "PROJECT_ROOT is not set")"
  fi
  if [[ ! -d "$PROJECT_ROOT" ]]; then
    die "$(msg "PROJECT_ROOT 不是目录: $PROJECT_ROOT" "PROJECT_ROOT is not a directory: $PROJECT_ROOT")"
  fi
  if [[ ! -w "$PROJECT_ROOT" ]]; then
    die "$(msg "PROJECT_ROOT 不可写: $PROJECT_ROOT" "PROJECT_ROOT is not writable: $PROJECT_ROOT")"
  fi
}
