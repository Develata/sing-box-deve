#!/usr/bin/env bash
# shellcheck disable=SC2034

SBD_ACTIVE_UPDATE_BASE_URL=""

append_unique_url() {
  local _out_var="$1" _url="$2"
  [[ -n "$_url" ]] || return 0
  # shellcheck disable=SC2034
  local -n _arr="$_out_var"
  local existing
  for existing in "${_arr[@]}"; do
    [[ "$existing" == "$_url" ]] && return 0
  done
  _arr+=("$_url")
}

resolve_update_base_urls() {
  local repo_ref="${SBD_REPO_REF:-main}"
  local urls=()

  if [[ -n "${SBD_UPDATE_BASE_URL:-}" ]]; then
    append_unique_url urls "$SBD_UPDATE_BASE_URL"
    append_unique_url urls "${SBD_UPDATE_BACKUP_BASE_URL:-}"
    printf '%s\n' "${urls[@]}"
    return 0
  fi

  local origin=""
  if command -v git >/dev/null 2>&1 && [[ -d "${PROJECT_ROOT}/.git" ]]; then
    origin="$(git -C "$PROJECT_ROOT" config --get remote.origin.url 2>/dev/null || true)"
  fi

  if [[ "$origin" =~ ^git@github.com:([^/]+)/([^/.]+)(\.git)?$ ]]; then
    append_unique_url urls "https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/${repo_ref}"
    append_unique_url urls "https://cdn.jsdelivr.net/gh/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}@${repo_ref}"
    append_unique_url urls "${SBD_UPDATE_BACKUP_BASE_URL:-}"
    printf '%s\n' "${urls[@]}"
    return 0
  fi

  if [[ "$origin" =~ ^https://github.com/([^/]+)/([^/.]+)(\.git)?$ ]]; then
    append_unique_url urls "https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/${repo_ref}"
    append_unique_url urls "https://cdn.jsdelivr.net/gh/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}@${repo_ref}"
    append_unique_url urls "${SBD_UPDATE_BACKUP_BASE_URL:-}"
    printf '%s\n' "${urls[@]}"
    return 0
  fi

  local repo_slug="${SBD_REPO_SLUG:-Develata/sing-box-deve}"
  if [[ "$repo_slug" =~ ^[^/]+/[^/]+$ ]]; then
    append_unique_url urls "https://raw.githubusercontent.com/${repo_slug}/${repo_ref}"
    append_unique_url urls "https://cdn.jsdelivr.net/gh/${repo_slug}@${repo_ref}"
    append_unique_url urls "${SBD_UPDATE_BACKUP_BASE_URL:-}"
    printf '%s\n' "${urls[@]}"
  fi
}

resolve_update_base_url() {
  resolve_update_base_url_by_mode "auto"
}

resolve_update_base_url_by_mode() {
  local mode="${1:-auto}" urls=() pick=""
  while IFS= read -r pick; do
    [[ -n "$pick" ]] && urls+=("$pick")
  done < <(resolve_update_base_urls)
  [[ "${#urls[@]}" -gt 0 ]] || {
    echo ""
    return 0
  }
  case "$mode" in
    primary) echo "${urls[0]}" ;;
    backup)
      if [[ "${#urls[@]}" -ge 2 ]]; then
        echo "${urls[1]}"
      else
        echo "${urls[0]}"
      fi
      ;;
    auto) echo "${urls[0]}" ;;
    *) die "Invalid update source mode: ${mode}" ;;
  esac
}

update_base_candidates() {
  local mode="${1:-auto}" primary backup
  case "$mode" in
    primary|backup) resolve_update_base_url_by_mode "$mode" ;;
    auto)
      primary="$(resolve_update_base_url_by_mode primary)"
      backup="$(resolve_update_base_url_by_mode backup)"
      [[ -n "$primary" ]] && echo "$primary"
      if [[ -n "$backup" && "$backup" != "$primary" ]]; then
        echo "$backup"
      fi
      ;;
    *) die "Invalid update source mode: ${mode}" ;;
  esac
}
