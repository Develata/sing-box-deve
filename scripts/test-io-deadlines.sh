#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/lib/load.sh"
io_test="$(mktemp -d)"; server_pid=""
trap '[[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true; rm -rf "$io_test"' EXIT
fail() { echo "[FAIL] $*" >&2; exit 1; }
python3 - "$io_test/port" <<'PY' &
import http.server, sys, threading, time
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/partial':
            self.send_response(200)
            self.send_header('Content-Length', '1000')
            self.end_headers()
            self.wfile.write(b'partial')
            self.wfile.flush()
        time.sleep(30)
    def log_message(self, *_): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
with open(sys.argv[1], 'w') as f: f.write(str(server.server_port))
server.serve_forever()
PY
server_pid=$!
for _ in {1..50}; do [[ ! -s "$io_test/port" ]] || break; sleep 0.1; done
[[ -s "$io_test/port" ]] || fail 'HTTP fixture failed to bind'
url="http://127.0.0.1:$(cat "$io_test/port")"
started=$SECONDS
if SBD_HTTP_TIMEOUT=1 sbd_http_small "$url/blackhole" > "$io_test/body"; then fail 'blackhole returned success'; fi
(( SECONDS - started <= 4 )) || fail 'metadata deadline exceeded'
printf 'valid-before\n' > "$io_test/artifact"
started=$SECONDS
if SBD_DOWNLOAD_MAX_TIME=1 SBD_DOWNLOAD_TOTAL_TIME=2 SBD_DOWNLOAD_RETRY_DELAY=0 download_file "$url/partial" "$io_test/artifact"; then fail 'partial response accepted'; fi
(( SECONDS - started <= 5 )) || fail 'download retry total budget exceeded'
[[ "$(cat "$io_test/artifact")" == valid-before ]] || fail 'partial download replaced valid artifact'
cat > "$io_test/block" <<'SH'
#!/usr/bin/env bash
trap '' TERM
exec sleep 60
SH
chmod +x "$io_test/block"
started=$SECONDS
if SBD_SERVICE_TIMEOUT=1 SBD_TIMEOUT_KILL_AFTER=1 sbd_service_op "$io_test/block"; then fail 'blocked service accepted'; fi
(( SECONDS - started <= 4 )) || fail 'service command lacked hard deadline'
mkdir "$io_test/bin"
cp "$io_test/block" "$io_test/bin/sshpass"
printf 'fixture\n' > "$io_test/known_hosts"
started=$SECONDS
if PATH="$io_test/bin:$PATH" SERV00_KNOWN_HOSTS_FILE="$io_test/known_hosts" SBD_SSH_TIMEOUT=1 SBD_TIMEOUT_KILL_AFTER=1 sbd_ssh_exec host user dummy true; then fail 'blocked SSH accepted'; fi
(( SECONDS - started <= 4 )) || fail 'SSH lacked hard deadline'

# Dedicated account FD: simulated SSH greedily reads stdin without losing rows.
PATH="$io_test/bin:$PATH"
SBD_CONFIG_DIR="$io_test/config"
AUTO_YES=true
SERV00_BOOTSTRAP_CMD=true
SERV00_ACCOUNTS_JSON='[{"host":"one.example","user":"one","pass":"fixture"},{"host":"two.example","user":"two","pass":"fixture"}]'
sbd_ssh_exec() { cat >/dev/null; printf '%s\n' "$1" >> "$io_test/accounts-seen"; }
provider_prepare_domain_runtime_artifacts() { return 0; }
provider_serv00_install lite sing-box vless-reality < /dev/null
[[ "$(wc -l < "$io_test/accounts-seen")" == 2 ]] || fail 'SSH consumed account stream'
printf '[OK] HTTP, service, SSH deadline and account-FD checks passed\n'
