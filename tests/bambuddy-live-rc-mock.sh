#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/bambuddy-live-rc.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OLD='ghcr.io/mikefox303/bambuddy:1.2.5.5-x2d.73@sha256:9abf0d5bfb612dd1f473a7632f2b7aa404ef06db759e979b388bd7466cc84fb0'
NEW='ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:dc627d618cc3d3252ae4ab33af74c4679c66a9a06e0e3bbb7aefa32d1a4d4a07'
MOCKBIN="$TMP/bin"
STATE="$TMP/state-image"
mkdir -p "$MOCKBIN"

cat >"$MOCKBIN/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
shift || true
case "$cmd" in
  inspect)
    joined="$*"
    if [[ "$joined" == *'.Config.Image'* ]]; then
      cat "$MOCK_STATE"
    elif [[ "$joined" == *'.HostConfig.NetworkMode'* ]]; then
      echo host
    elif [[ "$joined" == *'.State.Running'* ]]; then
      echo true
    else
      echo '{}'
    fi
    ;;
  exec)
    joined="$*"
    current="$(cat "$MOCK_STATE")"
    if [[ "${MOCK_FAIL_NEW_HEALTH:-0}" == 1 && "$current" == ghcr.io/maziggy/bambuddy:* && "$joined" == *'urllib.request'* ]]; then
      exit 1
    fi
    if [[ "$joined" == *' python -'* ]]; then
      cat >/dev/null || true
      echo 'mock python stdin check: PASS'
    fi
    exit 0
    ;;
  pull)
    echo "mock pull $*"
    ;;
  logs)
    echo 'mock bambuddy log'
    ;;
  rm)
    exit 0
    ;;
  *)
    echo "unexpected mock docker command: $cmd $*" >&2
    exit 1
    ;;
esac
SH

cat >"$MOCKBIN/umbreld" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
joined="$*"
if [[ "$joined" == *'apps.restart.mutate'* ]]; then
  image="$(grep -E 'ghcr\.io/(mikefox303|maziggy)/bambuddy:' "$APP_DIR/docker-compose.yml" | head -1 | sed 's/^[[:space:]]*//')"
  printf '%s\n' "$image" >"$MOCK_STATE"
  echo '{"status":"ok"}'
  exit 0
fi
if [[ "$joined" == *'apps.stop.mutate'* ]]; then
  echo '{"status":"ok"}'
  exit 0
fi
echo "unexpected mock umbreld command: $joined" >&2
exit 1
SH

cat >"$MOCKBIN/curl" <<'SH'
#!/usr/bin/env bash
exit 0
SH

cat >"$MOCKBIN/seq" <<'SH'
#!/usr/bin/env bash
echo 1
SH

cat >"$MOCKBIN/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH

chmod +x "$MOCKBIN"/*

make_fixture() {
  local app="$1"
  rm -rf "$app"
  mkdir -p "$app/data" "$app/logs"
  cat >"$app/docker-compose.yml" <<EOF
version: '3.7'
services:
  app_proxy:
    environment:
      APP_HOST: 192.168.0.100
      APP_PORT: 8000
      PROXY_AUTH_ADD: 'false'
    container_name: my3d-bambuddy_app_proxy_1
  server:
    image: >-
      $OLD
    restart: on-failure
    init: true
    network_mode: host
    cap_add:
      - NET_BIND_SERVICE
    environment:
      TZ: Europe/Kyiv
      PUID: '1000'
      PGID: '1000'
      PORT: '8000'
      VIRTUAL_PRINTER_ADVERTISE_ADDRESS: 192.168.0.100
      VIRTUAL_PRINTER_PASV_ADDRESS: 192.168.0.100
    volumes:
      - \${APP_DATA_DIR}/data:/app/data
      - \${APP_DATA_DIR}/logs:/app/logs
    container_name: my3d-bambuddy_server_1
EOF
  echo 'manifestVersion: 1.1' >"$app/umbrel-app.yml"
  echo 'dependencies: {}' >"$app/settings.yml"
  python3 - "$app/data/bambuddy.db" <<'PY'
import sqlite3, sys
p = sys.argv[1]
db = sqlite3.connect(p)
db.execute('create table marker (id integer primary key, value text)')
db.execute("insert into marker(value) values ('before')")
db.commit()
db.close()
PY
  printf '%s\n' "$OLD" >"$STATE"
}

export MOCK_STATE="$STATE"

APP1="$TMP/app-success"
make_fixture "$APP1"
OUT1="$TMP/success.out"
APP_DIR="$APP1" PATH="$MOCKBIN:$PATH" bash "$SCRIPT" >"$OUT1" 2>&1

grep -Fq 'LIVE_RC=PASS' "$OUT1"
grep -Fq 'NETWORK=host' "$OUT1"
grep -Fq "$NEW" "$APP1/docker-compose.yml"
! grep -Fq "$OLD" "$APP1/docker-compose.yml"
grep -Fq 'network_mode: host' "$APP1/docker-compose.yml"
grep -Fq 'VIRTUAL_PRINTER_ADVERTISE_ADDRESS: 192.168.0.100' "$APP1/docker-compose.yml"
grep -Fq 'VIRTUAL_PRINTER_PASV_ADDRESS: 192.168.0.100' "$APP1/docker-compose.yml"

echo 'mock live RC success path: PASS'

APP2="$TMP/app-rollback"
make_fixture "$APP2"
OUT2="$TMP/rollback.out"
set +e
MOCK_FAIL_NEW_HEALTH=1 APP_DIR="$APP2" PATH="$MOCKBIN:$PATH" bash "$SCRIPT" >"$OUT2" 2>&1
RC=$?
set -e

[[ "$RC" -eq 1 ]]
grep -Fq 'ROLLBACK=PASS' "$OUT2"
grep -Fq "$OLD" "$APP2/docker-compose.yml"
! grep -Fq "$NEW" "$APP2/docker-compose.yml"
grep -Fq 'network_mode: host' "$APP2/docker-compose.yml"
python3 - "$APP2/data/bambuddy.db" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
assert db.execute('pragma quick_check').fetchone()[0] == 'ok'
assert db.execute('select value from marker').fetchone()[0] == 'before'
db.close()
PY

echo 'mock live RC rollback path: PASS'
