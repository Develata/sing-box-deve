#!/usr/bin/env bash

clash_ruleset_dir() {
  echo "${SBD_DATA_DIR}/clash-ruleset"
}

clash_ruleset_tags() {
  echo "geosite-cn geoip-cn"
}

clash_ruleset_local_path() {
  local tag="$1"
  echo "$(clash_ruleset_dir)/${tag}.yaml"
}

clash_ruleset_repo_path() {
  local tag="$1"
  echo "${PROJECT_ROOT}/rulesets/clash/${tag}.yaml"
}

clash_rulesets_verify_repo_files() {
  local tag src
  for tag in $(clash_ruleset_tags); do
    src="$(clash_ruleset_repo_path "$tag")"
    [[ -s "$src" ]] || die "Bundled ruleset missing in repo: ${src}"
  done
}

clash_rulesets_sync_from_repo() {
  local force="${1:-false}"
  local tag src dst
  clash_rulesets_verify_repo_files
  mkdir -p "$(clash_ruleset_dir)"

  for tag in $(clash_ruleset_tags); do
    src="$(clash_ruleset_repo_path "$tag")"
    dst="$(clash_ruleset_local_path "$tag")"
    if [[ "$force" != "true" && -s "$dst" ]]; then
      continue
    fi
    cp -f "$src" "$dst"
  done
}

clash_rulesets_update_local() {
  clash_rulesets_sync_from_repo true
}

ensure_clash_rulesets_local() {
  local tag missing="false"
  for tag in $(clash_ruleset_tags); do
    [[ -s "$(clash_ruleset_local_path "$tag")" ]] || missing="true"
  done
  [[ "$missing" == "true" ]] || return 0

  log_info "$(msg "检测到规则集缺失，使用脚本内置规则集初始化" "Ruleset missing, initializing from bundled rulesets")"
  clash_rulesets_sync_from_repo false
}

sing_route_ruleset_dir() {
  echo "${SBD_DATA_DIR}/sing-ruleset"
}

sing_route_ruleset_tags() {
  echo "geosite-cn geoip-cn"
}

sing_route_ruleset_local_path() {
  local tag="$1"
  echo "$(sing_route_ruleset_dir)/${tag}.srs"
}

sing_route_ruleset_repo_path() {
  local tag="$1"
  echo "${PROJECT_ROOT}/rulesets/sing/${tag}.srs"
}

sing_route_rulesets_verify_repo_files() {
  local tag src
  for tag in $(sing_route_ruleset_tags); do
    src="$(sing_route_ruleset_repo_path "$tag")"
    [[ -s "$src" ]] || die "Bundled sing route ruleset missing in repo: ${src}"
  done
}

sing_route_rulesets_sync_from_repo() {
  local force="${1:-false}"
  local tag src dst
  sing_route_rulesets_verify_repo_files
  mkdir -p "$(sing_route_ruleset_dir)"

  for tag in $(sing_route_ruleset_tags); do
    src="$(sing_route_ruleset_repo_path "$tag")"
    dst="$(sing_route_ruleset_local_path "$tag")"
    if [[ "$force" != "true" && -s "$dst" ]]; then
      continue
    fi
    cp -f "$src" "$dst"
  done
}

sing_route_rulesets_update_local() {
  sing_route_rulesets_sync_from_repo true
}

ensure_sing_route_rulesets_local() {
  local tag missing="false"
  for tag in $(sing_route_ruleset_tags); do
    [[ -s "$(sing_route_ruleset_local_path "$tag")" ]] || missing="true"
  done
  [[ "$missing" == "true" ]] || return 0

  log_info "$(msg "检测到 sing-box 路由规则缺失，使用脚本内置规则集初始化" "Sing-box route ruleset missing, initializing from bundled rulesets")"
  sing_route_rulesets_sync_from_repo false
}

build_sing_route_rule_set_json() {
  local geosite geoip
  geosite="$(sing_route_ruleset_local_path geosite-cn)"
  geoip="$(sing_route_ruleset_local_path geoip-cn)"
  echo "\"rule_set\":[{\"tag\":\"geosite-cn\",\"type\":\"local\",\"format\":\"binary\",\"path\":\"${geosite}\"},{\"tag\":\"geoip-cn\",\"type\":\"local\",\"format\":\"binary\",\"path\":\"${geoip}\"}]"
}
