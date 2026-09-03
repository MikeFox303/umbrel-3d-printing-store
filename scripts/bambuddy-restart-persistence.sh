#!/usr/bin/env bash
set -euo pipefail

BAMBUDDY_APP_ID='my3d-bambuddy'
SPOOLMAN_APP_ID='my3d-spoolman'
APP_DIR="${APP_DIR:-/home/umbrel/umbrel/app-data/my3d-bambuddy}"
DB="$APP_DIR/data/bambuddy.db"
SERVER='my3d-bambuddy_server_1'
SPOOLMAN_SERVER='my3d-spoolman_server_1'
X2D_IP="${X2D_IP:-192.168.0.151}"
HOST_IP="${HOST_IP:-192.168.0.100}"
EXPECTED_IMAGE='ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:dc627d618cc3d3252ae4ab33af74c4679c66a9a06e0e3bbb7aefa32d1a4d4a07'

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

umbrel_cmd() {
  if [[ "$(id -u)" -eq 0 ]] && id umbrel >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    sudo -u umbrel umbreld client "$@"
  else
    umbreld client "$@"
  fi
}

restart_app() {
  local app_id="$1"
  umbrel_cmd apps.restart.mutate --appId "$app_id"
}

wait_bambuddy_health() {
  for _ in $(seq 1 120); do
    if docker inspect "$SERVER" >/dev/null 2>&1 \
      && [[ "$(docker inspect "$SERVER" --format '{{.State.Running}}' 2>/dev/null || true)" == true ]] \
      && [[ "$(docker inspect "$SERVER" --format '{{.Config.Image}}' 2>/dev/null || true)" == "$EXPECTED_IMAGE" ]] \
      && curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_spoolman_health() {
  for _ in $(seq 1 120); do
    if docker inspect "$SPOOLMAN_SERVER" >/dev/null 2>&1 \
      && [[ "$(docker inspect "$SPOOLMAN_SERVER" --format '{{.State.Running}}' 2>/dev/null || true)" == true ]] \
      && curl -fsS http://127.0.0.1:7912/ >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

assignment_snapshot() {
  python3 - "$DB" <<'PY'
import hashlib
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
rows = db.execute(
    "SELECT printer_id, ams_id, tray_id, spoolman_spool_id "
    "FROM spoolman_slot_assignments ORDER BY printer_id, ams_id, tray_id"
).fetchall()
db.close()
text = "\n".join(",".join(map(str, row)) for row in rows)
print(hashlib.sha256(text.encode()).hexdigest())
PY
}

print_assignments() {
  python3 - "$DB" <<'PY'
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
rows = db.execute(
    "SELECT printer_id, ams_id, tray_id, spoolman_spool_id "
    "FROM spoolman_slot_assignments ORDER BY printer_id, ams_id, tray_id"
).fetchall()
db.close()
print(f"Spoolman slot assignments: {len(rows)}")
for row in rows:
    print(f"  printer={row[0]} ams={row[1]} tray={row[2]} spoolman_spool={row[3]}")
PY
}

api_verify() {
  python3 - "$X2D_IP" <<'PY'
import json
import sys
import time
import urllib.error
import urllib.request

base = "http://127.0.0.1:8000/api/v1"
x2d_ip = sys.argv[1]


def get(path):
    with urllib.request.urlopen(base + path, timeout=10) as response:
        return json.load(response)


def printer_list():
    value = get("/printers/")
    if isinstance(value, dict):
        for key in ("items", "printers", "data"):
            if isinstance(value.get(key), list):
                return value[key]
    return value if isinstance(value, list) else []

printers = printer_list()
x2d = next(
    (
        p for p in printers
        if isinstance(p, dict)
        and (
            p.get("ip_address") == x2d_ip
            or "X2D" in str(p.get("model") or "").upper()
            or str(p.get("model") or "").upper() == "N6"
        )
    ),
    None,
)
if not x2d:
    raise SystemExit("X2D not found in Bambuddy API")

status = get(f"/printers/{x2d['id']}/status")
state = str(status.get("state") or "").upper()
print(f"X2D connected={status.get('connected')} state={state} ams_exists={status.get('ams_exists')}")
if not status.get("connected"):
    raise SystemExit("X2D is not connected after restart")
if state in {"RUNNING", "PAUSE", "PREPARE", "SLICING"}:
    raise SystemExit(f"printer unexpectedly active during restart test: {state}")

ams = status.get("ams") or []
tray_count = sum(len((unit or {}).get("tray") or []) for unit in ams if isinstance(unit, dict))
print(f"AMS units={len(ams)} tray_records={tray_count}")
if not status.get("ams_exists") or tray_count < 4:
    raise SystemExit("AMS 2 Pro telemetry did not recover after restart")

vp = get("/virtual-printers")
vps = vp.get("printers", []) if isinstance(vp, dict) else []
enabled = [v for v in vps if isinstance(v, dict) and v.get("enabled")]
print(f"Virtual printers configured={len(vps)} enabled={len(enabled)}")
if not enabled:
    raise SystemExit("no enabled Virtual Printer found after restart")
for item in enabled:
    runtime = item.get("status") or {}
    print(
        f"  VP id={item.get('id')} name={item.get('name')} "
        f"mode={item.get('mode')} running={runtime.get('running')}"
    )
    if not runtime.get("running"):
        raise SystemExit("enabled Virtual Printer did not recover after restart")

connected = False
last = None
for _ in range(30):
    try:
        last = get("/spoolman/status")
        connected = bool(last.get("enabled") and last.get("connected"))
    except Exception as exc:
        last = {"error": f"{type(exc).__name__}: {exc}"}
    if connected:
        break
    time.sleep(2)
print(f"Spoolman status={last}")
if not connected:
    raise SystemExit("Spoolman integration did not reconnect")
PY
}

for cmd in docker python3 curl grep umbreld; do
  need "$cmd"
done

[[ -f "$DB" ]] || fail "database not found: $DB"

IMAGE="$(docker inspect "$SERVER" --format '{{.Config.Image}}')"
NETWORK="$(docker inspect "$SERVER" --format '{{.HostConfig.NetworkMode}}')"
RUNNING="$(docker inspect "$SERVER" --format '{{.State.Running}}')"

[[ "$IMAGE" == "$EXPECTED_IMAGE" ]] || fail "unexpected Bambuddy image: $IMAGE"
[[ "$NETWORK" == host ]] || fail "Bambuddy is not using host networking"
[[ "$RUNNING" == true ]] || fail "Bambuddy is not running"

# Refuse to disturb an active printer.
python3 - "$X2D_IP" <<'PY'
import json
import sys
import urllib.request

base = "http://127.0.0.1:8000/api/v1"
x2d_ip = sys.argv[1]
ACTIVE = {"RUNNING", "PAUSE", "PREPARE", "SLICING"}

with urllib.request.urlopen(base + "/printers/", timeout=10) as response:
    printers = json.load(response)
if isinstance(printers, dict):
    for key in ("items", "printers", "data"):
        if isinstance(printers.get(key), list):
            printers = printers[key]
            break
if not isinstance(printers, list):
    raise SystemExit("cannot verify printer list")

x2d = next((p for p in printers if isinstance(p, dict) and p.get("ip_address") == x2d_ip), None)
if not x2d:
    raise SystemExit("cannot find X2D before restart")
with urllib.request.urlopen(f"{base}/printers/{x2d['id']}/status", timeout=10) as response:
    status = json.load(response)
state = str(status.get("state") or "").upper()
print(f"Preflight X2D state: {state}")
if state in ACTIVE:
    raise SystemExit(f"restart test blocked: X2D is active ({state})")
if not status.get("connected"):
    raise SystemExit("restart test blocked: X2D is not connected")
PY

BEFORE="$(assignment_snapshot)"
echo "Assignment snapshot before: $BEFORE"
print_assignments

echo
echo '=========================================='
echo ' RESTART BAMBUDDY'
echo '=========================================='
restart_app "$BAMBUDDY_APP_ID"
wait_bambuddy_health || fail "Bambuddy did not become healthy after restart"
api_verify
AFTER_BAMBUDDY="$(assignment_snapshot)"
echo "Assignment snapshot after Bambuddy restart: $AFTER_BAMBUDDY"
[[ "$AFTER_BAMBUDDY" == "$BEFORE" ]] || fail "Spoolman slot assignments changed after Bambuddy restart"
echo 'BAMBUDDY_RESTART_PERSISTENCE=PASS'

echo
echo '=========================================='
echo ' RESTART SPOOLMAN'
echo '=========================================='
restart_app "$SPOOLMAN_APP_ID"
wait_spoolman_health || fail "Spoolman did not become healthy after restart"
api_verify
AFTER_SPOOLMAN="$(assignment_snapshot)"
echo "Assignment snapshot after Spoolman restart: $AFTER_SPOOLMAN"
[[ "$AFTER_SPOOLMAN" == "$BEFORE" ]] || fail "Spoolman slot assignments changed after Spoolman restart"
echo 'SPOOLMAN_RESTART_PERSISTENCE=PASS'

echo
echo '=========================================='
echo ' RESULT'
echo '=========================================='
print_assignments
echo 'RESTART_PERSISTENCE=PASS'
echo "IMAGE=$(docker inspect "$SERVER" --format '{{.Config.Image}}')"
echo "NETWORK=$(docker inspect "$SERVER" --format '{{.HostConfig.NetworkMode}}')"
echo 'No database rows or settings were modified by this test; only Bambuddy and Spoolman were restarted.'
