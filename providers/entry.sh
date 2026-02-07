#!/usr/bin/env bash
set -euo pipefail

provider="${1:-}"
shift || true
[[ -n "$provider" ]] || {
  echo "Usage: providers/entry.sh <vps|serv00|sap|docker> [command] [args...]" >&2
  exit 1
}

case "$provider" in
  vps|serv00|sap|docker) ;;
  *)
    echo "Unsupported provider: $provider" >&2
    exit 1
    ;;
esac

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main="${root_dir}/sing-box-deve.sh"
[[ -x "$main" ]] || {
  echo "Main script not executable: ${main}" >&2
  exit 1
}

cmd="${1:-install}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  install)
    exec "$main" install --provider "$provider" "$@"
    ;;
  wizard|menu|list|panel|status|restart|logs|set-port|set-egress|set-route|set-share|split3|jump|sub|cfg|kernel|warp|sys|regen-nodes|update|version|settings|uninstall|doctor|fw|help)
    exec "$main" "$cmd" "$@"
    ;;
  *)
    # 兼容老用法：providers/<name>.sh --profile ... 等价于 install --provider <name> --profile ...
    exec "$main" install --provider "$provider" "$cmd" "$@"
    ;;
esac
