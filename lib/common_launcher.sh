#!/usr/bin/env bash

write_sb_launcher() {
  cat > /usr/local/bin/sb <<'SBEOF'
#!/usr/bin/env bash
set -euo pipefail

is_sbd_project_root() {
  local root="$1"
  [[ -x "$root/sing-box-deve.sh" && -f "$root/lib/common.sh" ]]
}

is_sbd_git_checkout() {
  local root="$1" origin=""
  is_sbd_project_root "$root" || return 1
  [[ -d "$root/.git" ]] || return 1
  if command -v git >/dev/null 2>&1; then
    origin="$(git -C "$root" config --get remote.origin.url 2>/dev/null || true)"
    [[ -z "$origin" || "$origin" == *sing-box-deve* ]] || return 1
  fi
}

read_sbd_version() {
  local root="$1"
  if [[ -f "$root/version" ]]; then
    tr -d '[:space:]' < "$root/version"
  else
    printf '%s\n' "v0.0.0"
  fi
}

normalize_sbd_version() {
  local raw="${1#v}" core major minor patch extra
  core="${raw%%[-+]*}"
  IFS=. read -r major minor patch extra <<< "$core"
  [[ -z "${extra:-}" ]] || return 1
  [[ "${major:-}" =~ ^[0-9]+$ ]] || return 1
  [[ "${minor:-0}" =~ ^[0-9]+$ ]] || return 1
  [[ "${patch:-0}" =~ ^[0-9]+$ ]] || return 1
  printf '%d.%d.%d\n' "$major" "${minor:-0}" "${patch:-0}"
}

sbd_version_ge() {
  local left right lm ln lp rm rn rp
  left="$(normalize_sbd_version "${1:-}")" || return 1
  right="$(normalize_sbd_version "${2:-}")" || return 1
  IFS=. read -r lm ln lp <<< "$left"
  IFS=. read -r rm rn rp <<< "$right"
  (( lm > rm )) && return 0
  (( lm < rm )) && return 1
  (( ln > rn )) && return 0
  (( ln < rn )) && return 1
  (( lp >= rp ))
}

choose_git_checkout_root() {
  local reference_root="${1:-}" reference_version candidate candidate_version
  local -a candidates=(
    "$PWD"
    "$PWD/sing-box-deve"
    "${HOME:-}/sing-box-deve"
    "/root/sing-box-deve"
    "/opt/sing-box-deve"
    "/usr/local/src/sing-box-deve"
  )

  if [[ -n "$reference_root" && -f "$reference_root/version" ]]; then
    reference_version="$(read_sbd_version "$reference_root")"
  else
    reference_version="v0.0.0"
  fi

  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    is_sbd_git_checkout "$candidate" || continue
    candidate_version="$(read_sbd_version "$candidate")"
    if sbd_version_ge "$candidate_version" "$reference_version"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

script_root=""

for _p in "/etc/sing-box-deve/runtime.env" "${HOME:-}/sing-box-deve/config/runtime.env"; do
  if [[ -f "$_p" ]]; then
    script_root="$(awk -F= '/^script_root=/{print substr($0, index($0, "=") + 1); exit}' "$_p" 2>/dev/null || true)"
    [[ -n "$script_root" ]] && break
  fi
done

git_root="$(choose_git_checkout_root "$script_root" || true)"
[[ -n "$git_root" ]] && script_root="$git_root"

if [[ -n "$script_root" && -x "$script_root/sing-box-deve.sh" ]]; then
  :
else
  script_root=""
  for candidate in "/opt/sing-box-deve/script" "/opt/sing-box-deve" "/usr/local/share/sing-box-deve" "$PWD/sing-box-deve"; do
    if is_sbd_project_root "$candidate"; then
      script_root="$candidate"
      break
    fi
  done
fi

if [[ -z "$script_root" || ! -x "$script_root/sing-box-deve.sh" ]]; then
  echo "[ERROR] Unable to locate sing-box-deve.sh. Reinstall with: sudo bash ./sing-box-deve.sh install ..." >&2
  exit 1
fi

case "${1:-}" in
  --print-root)
    printf '%s\n' "$script_root"
    exit 0
    ;;
  --print-version)
    read_sbd_version "$script_root"
    exit 0
    ;;
esac

if [[ $# -eq 0 ]]; then
  exec "$script_root/sing-box-deve.sh" menu
fi

exec "$script_root/sing-box-deve.sh" "$@"
SBEOF
  chmod +x /usr/local/bin/sb
}
