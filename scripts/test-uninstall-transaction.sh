#!/usr/bin/env bash
# SC2329 directives mark overrides called by sourced lifecycle code, or guards
# that fail if a forbidden service/filesystem operation is attempted.
# shellcheck disable=SC1091,SC2034,SC2317
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
uninstall_test="$(mktemp -d)"
trap 'rm -rf "$uninstall_test"' EXIT
fail() { echo "[FAIL] $*" >&2; exit 1; }

run_case() (
  local scenario="$1" base="$uninstall_test/$1"
  SBD_INSTALL_DIR="$base/install"
  SBD_CONFIG_DIR="$base/config"
  SBD_STATE_DIR="$base/state"
  SBD_RUNTIME_DIR="$base/run"
  SBD_HOST_STATE_DIR="$base/control"
  SBD_BIN_DIR="$SBD_INSTALL_DIR/bin"
  SBD_DATA_DIR="$SBD_INSTALL_DIR/data"
  SBD_ARGO_EXEC_FILE="$SBD_DATA_DIR/argo-exec"
  SBD_ARGO_TOKEN_FILE="$SBD_DATA_DIR/argo-token"
  SBD_RULES_FILE="$SBD_STATE_DIR/firewall-rules.db"
  SBD_CONTEXT_FILE="$SBD_STATE_DIR/context.env"
  SBD_SYSTEMD_DIR="$base/services"
  SBD_GLOBAL_BIN_DIR="$base/global"
  SBD_LAUNCHER_PATH="$SBD_GLOBAL_BIN_DIR/sb"
  SBD_SERVICE_FILE="$SBD_SYSTEMD_DIR/sing-box-deve.service"
  SBD_ARGO_SERVICE_FILE="$SBD_SYSTEMD_DIR/sing-box-deve-argo.service"
  SBD_FW_REPLAY_SERVICE_FILE="$SBD_SYSTEMD_DIR/sing-box-deve-fw-replay.service"
  SBD_WARP_SOCKS_SERVICE_FILE="$SBD_SYSTEMD_DIR/sing-box-deve-warp-socks5.service"
  SBD_INIT_SYSTEM=systemd SBD_USER_MODE=false
  SBD_MUTATION_DEPTH=0 SBD_ACTIVE_TRANSACTION=""
  mkdir -p "$SBD_CONFIG_DIR" "$SBD_STATE_DIR" "$SBD_BIN_DIR" "$SBD_DATA_DIR" "$SBD_RUNTIME_DIR" "$SBD_SYSTEMD_DIR" "$SBD_GLOBAL_BIN_DIR"
  if [[ "$scenario" == installed-killed ]]; then
    mkdir -p "$SBD_INSTALL_DIR/releases/test-runtime"
    python3 "$PROJECT_ROOT/scripts/runtime-archive.py" pack "$PROJECT_ROOT" "$base/runtime.tar.gz"
    python3 "$PROJECT_ROOT/scripts/runtime-archive.py" extract "$base/runtime.tar.gz" "$SBD_INSTALL_DIR/releases/test-runtime"
    ln -s "$SBD_INSTALL_DIR/releases/test-runtime" "$SBD_INSTALL_DIR/current"
    ln -s "$SBD_INSTALL_DIR/releases/test-runtime" "$SBD_INSTALL_DIR/previous"
    PROJECT_ROOT="$SBD_INSTALL_DIR/releases/test-runtime"
  fi
  printf 'provider=vps\nprofile=lite\nengine=sing-box\nprotocols=vless-reality\n' > "$SBD_CONFIG_DIR/runtime.env"
  sbd_write_env_kv script_root "$PROJECT_ROOT" >> "$SBD_CONFIG_DIR/runtime.env"
  printf 'config-before\n' > "$SBD_CONFIG_DIR/config.json"
  printf 'binary-before\n' > "$SBD_BIN_DIR/sing-box"
  printf 'identity-before\n' > "$SBD_DATA_DIR/uuid"
  printf 'nodes-before\n' > "$SBD_DATA_DIR/nodes.txt"
  mkdir -p "$SBD_DATA_DIR/sing-ruleset" "$SBD_INSTALL_DIR/cache"
  printf 'ruleset-before\n' > "$SBD_DATA_DIR/sing-ruleset/geosite-cn.srs"
  truncate -s 1G "$SBD_INSTALL_DIR/cache/excluded-large-cache"
  printf '# Managed by sing-box-deve: service-v1\nExecStart=%s/bin/sing-box\n' "$SBD_INSTALL_DIR" > "$SBD_SERVICE_FILE"
  printf '# Managed by sing-box-deve: service-v1\n' > "$SBD_ARGO_SERVICE_FILE"
  printf '# Managed by sing-box-deve: launcher-v1\n' > "$SBD_LAUNCHER_PATH"
  ln -s "$SBD_BIN_DIR/sing-box" "$SBD_GLOBAL_BIN_DIR/sing-box"
  printf 'iptables|tcp|2443|MYBOX:fixture:core:tcp:2443|date\niptables|udp|2443|MYBOX:fixture:core:udp:2443|date\n' > "$SBD_RULES_FILE"
  touch "$base/tcp" "$base/udp" "$base/sing-box-deve.active"
  if [[ "$scenario" == fresh-nohup ]]; then
    SBD_INIT_SYSTEM="nohup"
    command rm "$base/sing-box-deve.active"
    touch "$base/sing-box-deve-argo.active"
    cp /bin/sleep "$SBD_BIN_DIR/cloudflared"
    sbd_join_command_argv "$SBD_BIN_DIR/cloudflared" 60 > "$SBD_ARGO_EXEC_FILE"
  fi
  printf 'foreign\n' > "$base/unmanaged.conf"
  printf 'original-web\n' > "$base/web.conf"
  printf 'managed-web\n' > "$base/web-candidate"
  sbd_host_file_publish "$base/web.conf" "$base/web-candidate"
  sha256sum "$SBD_CONFIG_DIR/runtime.env" "$SBD_CONFIG_DIR/config.json" "$SBD_BIN_DIR/sing-box" "$SBD_DATA_DIR/uuid" "$SBD_SERVICE_FILE" "$SBD_ARGO_SERVICE_FILE" "$SBD_LAUNCHER_PATH" > "$base/before.sha256"
  # shellcheck disable=SC2329
  ensure_root() { :; }
  crontab() { return 1; }
  # shellcheck disable=SC2329
  sbd_service_probe() {
    if [[ "$scenario" == stop-query && "$1" == sing-box-deve && ! -e "$base/$1.active" && ! -e "$base/injected" ]]; then
      touch "$base/injected"; return 69
    fi
    if [[ -e "$base/$1.active" ]]; then echo 'active enabled'; else echo 'inactive disabled'; fi
  }
  # shellcheck disable=SC2329
  sbd_service_op() { :; }
  # shellcheck disable=SC2329
  sbd_service_stop() { command rm -f "$base/$1.active"; }
  # shellcheck disable=SC2329
  sbd_service_is_active() { [[ -e "$base/$1.active" ]]; }
  # shellcheck disable=SC2329
  sbd_service_daemon_reload() { [[ ! -e "$base/reload-fails" ]]; }
  # shellcheck disable=SC2329
  safe_service_restart() { [[ -f "$SBD_CONFIG_DIR/config.json" && -f "$SBD_BIN_DIR/sing-box" ]]; touch "$base/sing-box-deve.active"; }
  # shellcheck disable=SC2329
  provider_restart() { fail 'originally inactive Argo was started'; }
  # shellcheck disable=SC2329
  write_nodes_output() { :; }
  # shellcheck disable=SC2329
  fw_detect_backend_optional() { FW_BACKEND=iptables; }
  # shellcheck disable=SC2329
  fw_remove_rule_by_record() {
    [[ -e "$base/units-removed" || ! -f "$SBD_SERVICE_FILE" ]] || fail 'firewall tested before service removal'
    [[ ! -e "$SBD_LAUNCHER_PATH" ]] || fail 'firewall tested before launcher removal'
    command rm -f "$base/$2"
    if [[ "$scenario" == firewall && "$2" == tcp && ! -e "$base/injected" ]]; then touch "$base/injected"; return 42; fi
  }
  # shellcheck disable=SC2329
  fw_apply_rule_to_backend() { touch "$base/$2"; }
  # shellcheck disable=SC2329
  fw_cleanup_nftables_table() { :; }
  PURGE_MANAGED_HOST_CHANGES=false
  [[ "$scenario" != purge ]] || PURGE_MANAGED_HOST_CHANGES=true
  rm() {
    if [[ "$scenario" == purge && "$*" == *'/ownership/'* && "$(cat "$base/web.conf")" == original-web && ! -e "$base/injected" ]]; then
      touch "$base/injected"; return 43
    fi
    if [[ "$*" == '-rf -- '* && "$*" == *"$SBD_CONFIG_DIR"* && ! -e "$base/injected" ]]; then
      case "$scenario" in
        deletion|killed|fresh-recover|fresh-nohup|installed-killed|rollback-fails|external)
          command rm -rf -- "$SBD_CONFIG_DIR" "$SBD_INSTALL_DIR"
          touch "$base/injected"
          [[ "$scenario" != rollback-fails ]] || touch "$base/reload-fails"
          if [[ "$scenario" == external ]]; then mkdir "$SBD_CONFIG_DIR"; printf 'user-edit\n' > "$SBD_CONFIG_DIR/config.json"; fi
          [[ "$scenario" != killed && "$scenario" != installed-killed && "$scenario" != fresh-recover && "$scenario" != fresh-nohup ]] || kill -KILL "$BASHPID"
          return 44 ;;
      esac
    fi
    command rm "$@"
  }
  if [[ "$scenario" == foreign-service ]]; then
    command rm "$SBD_SERVICE_FILE"
    if provider_uninstall false; then fail 'service without ownership accepted'; fi
    [[ -e "$base/sing-box-deve.active" && -f "$SBD_LAUNCHER_PATH" && ! -L "$SBD_HOST_STATE_DIR/transactions/active" ]]
    printf '[OK] uninstall foreign service rejected before quiesce\n'
    return 0
  elif [[ "$scenario" == success ]]; then
    provider_uninstall true
    verify_uninstall
    [[ -z "$(find "$SBD_HOST_STATE_DIR/transactions" -mindepth 1 -print -quit)" ]]
    local -a backups=("$SBD_INSTALL_DIR".backup-*/files/config/config.json)
    [[ -f "${backups[0]}" ]]
    [[ "$(cat "$base/unmanaged.conf")" == foreign ]]
  else
    if provider_uninstall false; then fail "$scenario uninstall returned success"; fi
    [[ -e "$base/injected" ]] || fail "$scenario did not reach the injection boundary"
    if [[ "$scenario" == killed || "$scenario" == fresh-recover || "$scenario" == fresh-nohup || "$scenario" == installed-killed || "$scenario" == rollback-fails || "$scenario" == external ]]; then
      [[ -L "$SBD_HOST_STATE_DIR/transactions/active" ]] || fail 'lost unfinished transaction'
      transaction="$(readlink -f "$SBD_HOST_STATE_DIR/transactions/active")"
      bash -n "$transaction/recover.sh"
      [[ -f "$transaction/rescue/lib/providers_uninstall_transaction.sh" ]]
      [[ "$(du -sm "$transaction" | cut -f1)" -lt 30 ]] || fail 'uninstall copied cache'
      if [[ "$scenario" == external ]]; then
        if sbd_with_mutation_lock true; then fail 'external edit accepted by rollback'; fi
        [[ "$(cat "$SBD_CONFIG_DIR/config.json")" == user-edit ]]
        command rm "$SBD_CONFIG_DIR/config.json"
      fi
      command rm -f "$base/reload-fails"
      if [[ "$scenario" == fresh-nohup ]]; then
        mkdir "$base/fake-bin"
        cat > "$base/fake-bin/crontab" <<'SH'
#!/usr/bin/env bash
set -eu
case "$1" in -l) [[ -f "$fixture_base/cron" ]] && cat "$fixture_base/cron" ;; -) cat > "$fixture_base/cron" ;; *) exit 98 ;; esac
SH
        chmod +x "$base/fake-bin/crontab"
        # Replay is mocked only at the executable boundary in this fresh shell.
        cat > "$base/fake-bin/iptables" <<'SH'
#!/usr/bin/env bash
set -eu
proto=""
args=("$@")
for ((i=0; i<$#; i++)); do [[ "${args[i]}" != -p ]] || proto="${args[i+1]}"; done
case "$1" in
  -C) [[ -z "$proto" || -f "$fixture_base/$proto" ]] ;;
  -N|-S|-I) : ;;
  -A) touch "$fixture_base/$proto" ;;
  *) exit 98 ;;
esac
SH
        chmod +x "$base/fake-bin/iptables"
        timeout -k 2s 30s env "PATH=$base/fake-bin:$PATH" "fixture_base=$base" bash "$transaction/recover.sh"
        nohup_is_active sing-box-deve-argo || fail 'originally active Argo was not recovered in a fresh nohup process'
        nohup_stop_service sing-box-deve-argo
      elif [[ "$scenario" == fresh-recover ]]; then
        mkdir "$base/fake-bin"
        cat > "$base/fake-bin/systemctl" <<'SH'
#!/usr/bin/env bash
set -eu
name="${*: -1}"; name="${name%.service}"
case "$1" in
  show) [[ -f "$fixture_base/services/$name.service" ]] && echo loaded || echo not-found ;;
  daemon-reload|enable|disable) : ;;
  stop) rm -f "$fixture_base/$name.active" ;;
  restart|start)
    [[ "$name" == sing-box-deve && -f "$fixture_base/config/config.json" && -f "$fixture_base/install/bin/sing-box" ]]
    touch "$fixture_base/$name.active" ;;
  is-active) [[ -f "$fixture_base/$name.active" ]] ;;
  *) exit 98 ;;
esac
SH
        cat > "$base/fake-bin/iptables" <<'SH'
#!/usr/bin/env bash
set -eu
proto=""
args=("$@")
for ((i=0; i<$#; i++)); do [[ "${args[i]}" != -p ]] || proto="${args[i+1]}"; done
case "$1" in
  -C) [[ -z "$proto" || -f "$fixture_base/$proto" ]] ;;
  -N|-S|-I) : ;;
  -A) touch "$fixture_base/$proto" ;;
  *) exit 98 ;;
esac
SH
        chmod +x "$base/fake-bin/"*
        timeout -k 2s 30s env "PATH=$base/fake-bin:$PATH" "fixture_base=$base" bash "$transaction/recover.sh"
      else
        sbd_with_mutation_lock true
      fi
      if [[ "$scenario" == installed-killed ]]; then
        sbd_release_verify "$(readlink -f "$SBD_INSTALL_DIR/current")"
        [[ "$(readlink "$SBD_INSTALL_DIR/previous")" == "$SBD_INSTALL_DIR/releases/test-runtime" ]]
      fi
    fi
    sha256sum -c "$base/before.sha256" >/dev/null || fail "$scenario did not restore critical files"
    [[ -L "$SBD_GLOBAL_BIN_DIR/sing-box" && "$(readlink "$SBD_GLOBAL_BIN_DIR/sing-box")" == "$SBD_BIN_DIR/sing-box" ]]
    if [[ "$scenario" == fresh-nohup ]]; then
      [[ ! -e "$base/sing-box-deve.active" ]]
    else [[ -e "$base/sing-box-deve.active" && ! -e "$base/sing-box-deve-argo.active" ]]; fi
    [[ -e "$base/tcp" && -e "$base/udp" && ! -L "$SBD_HOST_STATE_DIR/transactions/active" ]]
    [[ "$(cat "$base/web.conf")" == managed-web && "$(cat "$base/unmanaged.conf")" == foreign ]]
    sbd_host_file_unchanged "$base/web.conf"
    [[ "$(cat "$SBD_DATA_DIR/sing-ruleset/geosite-cn.srs")" == ruleset-before ]]
  fi
  printf '[OK] uninstall %s\n' "$scenario"
)
for scenario in foreign-service stop-query firewall purge deletion killed fresh-recover fresh-nohup installed-killed rollback-fails external success; do run_case "$scenario"; done
