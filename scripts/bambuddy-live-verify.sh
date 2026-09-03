#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/home/umbrel/umbrel/app-data/my3d-bambuddy}"
COMPOSE="$APP_DIR/docker-compose.yml"
DB="$APP_DIR/data/bambuddy.db"
SERVER='my3d-bambuddy_server_1'
X2D_IP="${X2D_IP:-192.168.0.151}"
HOST_IP="${HOST_IP:-192.168.0.100}"
EXPECTED_IMAGE='ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:dc627d618cc3d3252ae4ab33af74c4679c66a9a06e0e3bbb7aefa32d1a4d4a07'

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

for cmd in docker python3 curl grep; do
  command -v "$cmd" >/dev/null 2>&1 || fail "required command not found: $cmd"
done

[[ -f "$COMPOSE" ]] || fail "compose not found: $COMPOSE"
[[ -f "$DB" ]] || fail "database not found: $DB"

echo '=========================================='
echo ' LIVE CONTAINER / NETWORK'
echo '=========================================='

IMAGE="$(docker inspect "$SERVER" --format '{{.Config.Image}}')"
NETWORK="$(docker inspect "$SERVER" --format '{{.HostConfig.NetworkMode}}')"
RUNNING="$(docker inspect "$SERVER" --format '{{.State.Running}}')"

echo "Image:   $IMAGE"
echo "Network: $NETWORK"
echo "Running: $RUNNING"

[[ "$IMAGE" == "$EXPECTED_IMAGE" ]] || fail 'official immutable image is not running'
[[ "$NETWORK" == host ]] || fail 'host networking is not active'
[[ "$RUNNING" == true ]] || fail 'Bambuddy container is not running'

grep -Fq 'network_mode: host' "$COMPOSE" || fail 'compose lost host networking'
grep -Fq "APP_HOST: $HOST_IP" "$COMPOSE" || fail 'compose APP_HOST changed'
grep -Fq "VIRTUAL_PRINTER_ADVERTISE_ADDRESS: $HOST_IP" "$COMPOSE" || fail 'Virtual Printer advertise address changed'
grep -Fq "VIRTUAL_PRINTER_PASV_ADDRESS: $HOST_IP" "$COMPOSE" || fail 'Virtual Printer PASV address changed'
grep -Fq 'NET_BIND_SERVICE' "$COMPOSE" || fail 'NET_BIND_SERVICE capability missing'

echo 'Virtual Printer compose invariants: PASS'

echo
echo '=========================================='
echo ' HEALTH / UMBREL PROXY'
echo '=========================================='

curl -fsS http://127.0.0.1:8000/health
printf '\n'
curl -fsS http://127.0.0.1:8280/health >/dev/null

echo 'Direct health: PASS'
echo 'Umbrel proxy health: PASS'

echo
echo '=========================================='
echo ' ACTUAL LIVE CONTAINER -> X2D'
echo '=========================================='

docker exec "$SERVER" python -c '
import socket, sys
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
' "$X2D_IP"

echo
echo '=========================================='
echo ' BAMBuddy API: X2D / AMS / SPOOLMAN / VP'
echo '=========================================='

python3 - "$X2D_IP" <<'PY'
import json
import sys
import urllib.error
import urllib.request

base = "http://127.0.0.1:8000/api/v1"
x2d_ip = sys.argv[1]


def get(path):
    try:
        with urllib.request.urlopen(base + path, timeout=10) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            raise SystemExit(
                f"API verification requires Bambuddy authentication ({exc.code}); "
                "verify X2D/AMS/Spoolman/Virtual Printer in the UI instead"
            )
        raise


printers = get("/printers")
if isinstance(printers, dict):
    for key in ("items", "printers", "data"):
        if isinstance(printers.get(key), list):
            printers = printers[key]
            break
if not isinstance(printers, list) or not printers:
    raise SystemExit("No printers returned by Bambuddy API")

x2d = None
for printer in printers:
    if not isinstance(printer, dict):
        continue
    if printer.get("ip_address") == x2d_ip:
        x2d = printer
        break
    model = str(printer.get("model") or "").upper()
    if "X2D" in model or model == "N6":
        x2d = printer
        break

if not x2d:
    raise SystemExit(f"X2D {x2d_ip} not found in Bambuddy printer list")

pid = x2d["id"]
status = get(f"/printers/{pid}/status")
print(f"Printer: {x2d.get('name')} model={x2d.get('model')} ip={x2d.get('ip_address')}")
print(f"Connected: {status.get('connected')}")
print(f"State: {status.get('state')}")
print(f"Progress: {status.get('progress')}")
print(f"AMS exists: {status.get('ams_exists')}")
ams = status.get("ams") or []
print(f"AMS units: {len(ams)}")
for unit in ams:
    if not isinstance(unit, dict):
        continue
    trays = unit.get("trays") or []
    print(f"  AMS id={unit.get('id')} humidity={unit.get('humidity')} trays={len(trays)}")
    for tray in trays:
        if isinstance(tray, dict):
            print(
                "    tray="
                f"{tray.get('id')} type={tray.get('tray_type')} "
                f"color={tray.get('tray_color')} remain={tray.get('remain')}"
            )

if not status.get("connected"):
    raise SystemExit("X2D is not connected in Bambuddy")
if not status.get("ams_exists") or not ams:
    raise SystemExit("AMS 2 Pro telemetry is missing")

spoolman = get("/spoolman/status")
print(
    "Spoolman: "
    f"enabled={spoolman.get('enabled')} connected={spoolman.get('connected')} "
    f"url={spoolman.get('url')}"
)
if not spoolman.get("enabled"):
    raise SystemExit("Spoolman is not enabled")
if not spoolman.get("connected"):
    raise SystemExit("Spoolman is not connected")

vp = get("/virtual-printers")
vps = vp.get("printers", []) if isinstance(vp, dict) else []
print(f"Virtual printers configured: {len(vps)}")
for item in vps:
    if not isinstance(item, dict):
        continue
    runtime = item.get("status") or {}
    print(
        f"  VP id={item.get('id')} name={item.get('name')} "
        f"enabled={item.get('enabled')} mode={item.get('mode')} "
        f"model={item.get('model')} bind_ip={item.get('bind_ip')} "
        f"running={runtime.get('running')} pending_files={runtime.get('pending_files')}"
    )

enabled_vps = [v for v in vps if isinstance(v, dict) and v.get("enabled")]
if enabled_vps:
    stopped = [v for v in enabled_vps if not (v.get("status") or {}).get("running")]
    if stopped:
        raise SystemExit("At least one enabled Virtual Printer is not running")
    print("Enabled Virtual Printer runtime: PASS")
else:
    print("Enabled Virtual Printer runtime: NOT EXERCISED (no enabled VP)")

print("Bambuddy API verification: PASS")
PY

echo
echo '=========================================='
echo ' DATABASE'
echo '=========================================='

python3 - "$DB" <<'PY'
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
check = db.execute("PRAGMA quick_check").fetchone()[0]
print("quick_check:", check)
print("tables:", db.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0])

assignments = db.execute(
    "SELECT printer_id, ams_id, tray_id, spoolman_spool_id "
    "FROM spoolman_slot_assignments ORDER BY printer_id, ams_id, tray_id"
).fetchall()
print(f"Spoolman slot assignments: {len(assignments)}")
for row in assignments:
    print(f"  printer={row[0]} ams={row[1]} tray={row[2]} spoolman_spool={row[3]}")

db.close()
if check != "ok":
    raise SystemExit(1)
PY

echo
echo '=========================================='
echo ' RESULT'
echo '=========================================='
echo 'LIVE_VERIFY=PASS'
echo "IMAGE=$IMAGE"
echo "NETWORK=$NETWORK"
echo 'This script is read-only; no containers, database rows, or settings were changed.'
