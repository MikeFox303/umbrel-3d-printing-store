#!/usr/bin/env bash
set -euo pipefail

APP_ID='my3d-bambuddy'
APP_DIR="${APP_DIR:-/home/umbrel/umbrel/app-data/my3d-bambuddy}"
COMPOSE="$APP_DIR/docker-compose.yml"
DATA_DIR="$APP_DIR/data"
DB="$DATA_DIR/bambuddy.db"
SERVER='my3d-bambuddy_server_1'
PROXY='my3d-bambuddy_app_proxy_1'
X2D_IP="${X2D_IP:-192.168.0.151}"
HOST_IP="${HOST_IP:-192.168.0.100}"

OLD_IMAGE='ghcr.io/mikefox303/bambuddy:1.2.5.5-x2d.73@sha256:9abf0d5bfb612dd1f473a7632f2b7aa404ef06db759e979b388bd7466cc84fb0'
NEW_IMAGE='ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:dc627d618cc3d3252ae4ab33af74c4679c66a9a06e0e3bbb7aefa32d1a4d4a07'

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$APP_DIR/live-rc-backup-$STAMP"
BACKUP_COMPOSE="$BACKUP_ROOT/docker-compose.yml.x2d73-host"
BACKUP_DB="$BACKUP_ROOT/bambuddy-before-live-rc.db"
BACKUP_MANIFEST="$BACKUP_ROOT/umbrel-app.yml"
BACKUP_SETTINGS="$BACKUP_ROOT/settings.yml"
LIVE_LOG="$BACKUP_ROOT/official-live.log"
ROLLBACK_LOG="$BACKUP_ROOT/rollback.log"

fail() {
  echo "ERROR: $*" >&2
  return 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

umbrel_cmd() {
  if [[ "$(id -u)" -eq 0 ]] && id umbrel >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    sudo -u umbrel umbreld client "$@"
  else
    umbreld client "$@"
  fi
}

restart_app() {
  umbrel_cmd apps.restart.mutate --appId "$APP_ID"
}

stop_app() {
  umbrel_cmd apps.stop.mutate --appId "$APP_ID" >/dev/null 2>&1 || true
}

wait_container_health() {
  local expected_image="$1"
  local tries="${2:-120}"
  local i running image
  for i in $(seq 1 "$tries"); do
    if docker inspect "$SERVER" >/dev/null 2>&1; then
      running="$(docker inspect "$SERVER" --format '{{.State.Running}}' 2>/dev/null || true)"
      image="$(docker inspect "$SERVER" --format '{{.Config.Image}}' 2>/dev/null || true)"
      if [[ "$running" == true && "$image" == "$expected_image" ]]; then
        if docker exec "$SERVER" python -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=2)' >/dev/null 2>&1; then
          return 0
        fi
      fi
    fi
    sleep 1
  done
  return 1
}

sqlite_backup() {
  local src="$1"
  local dst="$2"
  python3 - "$src" "$dst" <<'PY'
import sqlite3
import sys
src_path, dst_path = sys.argv[1], sys.argv[2]
src = sqlite3.connect(f"file:{src_path}?mode=ro", uri=True)
dst = sqlite3.connect(dst_path)
with dst:
    src.backup(dst)
check = dst.execute("PRAGMA quick_check").fetchone()[0]
print("backup quick_check:", check)
print("backup tables:", dst.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0])
src.close()
dst.close()
if check != "ok":
    raise SystemExit(1)
PY
}

sqlite_check() {
  python3 - "$1" <<'PY'
import sqlite3
import sys
p = sys.argv[1]
db = sqlite3.connect(p)
check = db.execute("PRAGMA quick_check").fetchone()[0]
print("production quick_check:", check)
print("production tables:", db.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0])
db.close()
if check != "ok":
    raise SystemExit(1)
PY
}

verify_compose_invariants() {
  grep -Fq 'network_mode: host' "$COMPOSE"
  grep -Fq "APP_HOST: $HOST_IP" "$COMPOSE"
  grep -Fq "VIRTUAL_PRINTER_ADVERTISE_ADDRESS: $HOST_IP" "$COMPOSE"
  grep -Fq "VIRTUAL_PRINTER_PASV_ADDRESS: $HOST_IP" "$COMPOSE"
  grep -Fq 'NET_BIND_SERVICE' "$COMPOSE"
}

verify_x2d_ports() {
  docker exec "$SERVER" python - "$X2D_IP" <<'PY'
import socket
import sys
host = sys.argv[1]
failed = False
for port, name in [(8883, "MQTT TLS"), (990, "FTPS"), (322, "RTSPS/Camera"), (6000, "LiveView/Camera")]:
    s = socket.socket()
    s.settimeout(5)
    try:
        s.connect((host, port))
        print(f"{host}:{port:<5} {name:<18} OPEN")
    except Exception as exc:
        failed = True
        print(f"{host}:{port:<5} {name:<18} FAIL ({type(exc).__name__}: {exc})")
    finally:
        s.close()
if failed:
    raise SystemExit(1)
PY
}

check_not_printing() {
  # Best-effort guard using the same local Bambuddy API the UI uses. If auth or
  # an API-shape change prevents a reliable determination, fail closed instead
  # of restarting Bambuddy while the X2D might be printing.
  docker exec "$SERVER" python - <<'PY'
import json
import urllib.request

ACTIVE = {"RUNNING", "PAUSE", "PREPARE", "SLICING"}
base = "http://127.0.0.1:8000/api/v1"

try:
    with urllib.request.urlopen(base + "/printers", timeout=4) as r:
        printers = json.load(r)
except Exception as exc:
    raise SystemExit(f"cannot verify printer idle state: {type(exc).__name__}: {exc}")

if isinstance(printers, dict):
    for key in ("items", "printers", "data"):
        if isinstance(printers.get(key), list):
            printers = printers[key]
            break

if not isinstance(printers, list) or not printers:
    raise SystemExit("cannot verify printer idle state: printer list unavailable")

checked = 0
for p in printers:
    pid = p.get("id") if isinstance(p, dict) else None
    if pid is None:
        continue
    try:
        with urllib.request.urlopen(f"{base}/printers/{pid}/status", timeout=4) as r:
            status = json.load(r)
    except Exception as exc:
        raise SystemExit(f"cannot verify printer {pid} idle state: {type(exc).__name__}: {exc}")
    state = str(status.get("state") or "").upper()
    name = p.get("name") or p.get("serial_number") or f"id={pid}"
    print(f"Printer {name}: state={state or 'UNKNOWN'}")
    if state in ACTIVE:
        raise SystemExit(f"migration blocked: printer {name} is active ({state})")
    if not state:
        raise SystemExit(f"cannot verify printer {name} idle state: empty state")
    checked += 1

if checked == 0:
    raise SystemExit("cannot verify printer idle state: no printer status checked")
print("Printer idle-state guard: PASS")
PY
}

rollback() {
  local reason="$1"
  trap - ERR INT TERM
  echo
  echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
  echo ' LIVE RC FAILED — AUTOMATIC ROLLBACK'
  echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
  echo "Reason: $reason"

  stop_app
  docker rm -f "$SERVER" "$PROXY" >/dev/null 2>&1 || true

  cp -a "$BACKUP_COMPOSE" "$COMPOSE"
  cp -a "$BACKUP_DB" "$DB"
  rm -f "$DATA_DIR/bambuddy.db-wal" "$DATA_DIR/bambuddy.db-shm"
  chown umbrel:umbrel "$COMPOSE" >/dev/null 2>&1 || true
  chown 1000:1000 "$DB" >/dev/null 2>&1 || true

  if restart_app; then
    if wait_container_health "$OLD_IMAGE" 120; then
      docker logs "$SERVER" >"$ROLLBACK_LOG" 2>&1 || true
      echo 'ROLLBACK=PASS'
      echo "ROLLBACK_IMAGE=$(docker inspect "$SERVER" --format '{{.Config.Image}}')"
      echo "ROLLBACK_NETWORK=$(docker inspect "$SERVER" --format '{{.HostConfig.NetworkMode}}')"
      echo "BACKUP_DIR=$BACKUP_ROOT"
      exit 1
    fi
  fi

  docker logs "$SERVER" >"$ROLLBACK_LOG" 2>&1 || true
  echo 'ROLLBACK=FAILED'
  echo "Manual recovery files are preserved in: $BACKUP_ROOT"
  exit 2
}

on_error() {
  local rc=$?
  rollback "command failed with exit code $rc at line ${BASH_LINENO[0]}"
}

for cmd in docker python3 grep diff curl umbreld; do
  need "$cmd"
done

[[ -f "$COMPOSE" ]] || { echo "ERROR: compose not found: $COMPOSE" >&2; exit 1; }
[[ -f "$DB" ]] || { echo "ERROR: database not found: $DB" >&2; exit 1; }

echo '=========================================='
echo ' PRE-FLIGHT: OBSERVED LIVE BASELINE'
echo '=========================================='

CURRENT_IMAGE="$(docker inspect "$SERVER" --format '{{.Config.Image}}')"
CURRENT_NETWORK="$(docker inspect "$SERVER" --format '{{.HostConfig.NetworkMode}}')"
CURRENT_RUNNING="$(docker inspect "$SERVER" --format '{{.State.Running}}')"

echo "Current image:   $CURRENT_IMAGE"
echo "Current network: $CURRENT_NETWORK"
echo "Current running: $CURRENT_RUNNING"

[[ "$CURRENT_IMAGE" == "$OLD_IMAGE" ]] || { echo 'ERROR: live image is not the accepted x2d.73 rollback baseline' >&2; exit 1; }
[[ "$CURRENT_NETWORK" == host ]] || { echo 'ERROR: live Bambuddy is not using host networking' >&2; exit 1; }
[[ "$CURRENT_RUNNING" == true ]] || { echo 'ERROR: live Bambuddy is not running' >&2; exit 1; }
verify_compose_invariants || { echo 'ERROR: current compose does not preserve required Virtual Printer host invariants' >&2; exit 1; }

docker exec "$SERVER" python -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=3)' >/dev/null

echo 'Current health: PASS'
check_not_printing

echo
echo '=========================================='
echo ' BACKUP'
echo '=========================================='

mkdir -p "$BACKUP_ROOT"
chmod 700 "$BACKUP_ROOT"
cp -a "$COMPOSE" "$BACKUP_COMPOSE"
[[ -f "$APP_DIR/umbrel-app.yml" ]] && cp -a "$APP_DIR/umbrel-app.yml" "$BACKUP_MANIFEST"
[[ -f "$APP_DIR/settings.yml" ]] && cp -a "$APP_DIR/settings.yml" "$BACKUP_SETTINGS"
sqlite_backup "$DB" "$BACKUP_DB"

echo "Backup directory: $BACKUP_ROOT"

trap on_error ERR
trap 'rollback "interrupted"' INT TERM

echo
echo '=========================================='
echo ' PREPARE OFFICIAL RC — IMAGE ONLY'
echo '=========================================='

python3 - "$COMPOSE" "$OLD_IMAGE" "$NEW_IMAGE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
old, new = sys.argv[2], sys.argv[3]
text = p.read_text()
count = text.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one old image reference, found {count}")
p.write_text(text.replace(old, new))
PY

chown umbrel:umbrel "$COMPOSE" >/dev/null 2>&1 || true
chmod 644 "$COMPOSE"

verify_compose_invariants
grep -Fq "$NEW_IMAGE" "$COMPOSE"
! grep -Fq "$OLD_IMAGE" "$COMPOSE"

echo 'Only intended compose difference:'
diff -u "$BACKUP_COMPOSE" "$COMPOSE" || true

CHANGE_LINES="$({ diff -U0 "$BACKUP_COMPOSE" "$COMPOSE" || true; } | grep -E '^[+-][[:space:]]+ghcr\.io/' | wc -l | tr -d ' ')"
[[ "$CHANGE_LINES" == 2 ]] || fail 'compose changed beyond the single image replacement'

echo
echo '=========================================='
echo ' PULL OFFICIAL IMAGE'
echo '=========================================='
docker pull "$NEW_IMAGE"

echo
echo '=========================================='
echo ' RESTART THROUGH UMBREL'
echo '=========================================='
restart_app

wait_container_health "$NEW_IMAGE" 120 || fail 'official Bambuddy did not become healthy'
docker logs "$SERVER" >"$LIVE_LOG" 2>&1 || true

echo
echo '=========================================='
echo ' VERIFY LIVE RC'
echo '=========================================='

LIVE_IMAGE="$(docker inspect "$SERVER" --format '{{.Config.Image}}')"
LIVE_NETWORK="$(docker inspect "$SERVER" --format '{{.HostConfig.NetworkMode}}')"

echo "Image:   $LIVE_IMAGE"
echo "Network: $LIVE_NETWORK"

[[ "$LIVE_IMAGE" == "$NEW_IMAGE" ]] || fail 'wrong image is running'
[[ "$LIVE_NETWORK" == host ]] || fail 'host networking was not preserved'
verify_compose_invariants

curl -fsS http://127.0.0.1:8000/health >/dev/null
curl -fsS http://127.0.0.1:8280/health >/dev/null

echo 'Bambuddy direct health: PASS'
echo 'Umbrel app-proxy health: PASS'

verify_x2d_ports
sqlite_check "$DB"

trap - ERR INT TERM

echo
echo '=========================================='
echo ' LIVE RC TECHNICAL RESULT'
echo '=========================================='
echo 'LIVE_RC=PASS'
echo "IMAGE=$LIVE_IMAGE"
echo "NETWORK=$LIVE_NETWORK"
echo "HOST_IP=$HOST_IP"
echo "X2D_IP=$X2D_IP"
echo "BACKUP_DIR=$BACKUP_ROOT"
echo 'Virtual Printer host-network compose was preserved; only the Bambuddy image changed.'
echo 'No publication or PR merge was performed.'
