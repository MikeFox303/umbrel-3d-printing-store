#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/home/umbrel/umbrel/app-data/my3d-bambuddy}"
COMPOSE="$APP_DIR/docker-compose.yml"
DB="$APP_DIR/data/bambuddy.db"
SERVER='my3d-bambuddy_server_1'
X2D_IP="${X2D_IP:-192.168.0.151}"
HOST_IP="${HOST_IP:-192.168.0.100}"
APP_PORT="${APP_PORT:-8280}"
BIND_IP="${BIND_IP:-10.21.0.2}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

for cmd in docker python3 curl grep sed; do
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
CONTAINER_IP="$(docker inspect "$SERVER" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
COMPOSE_IMAGE="$(sed -n '/^  server:/,/^  [^ ]/p' "$COMPOSE" | sed -n 's/^    image:[[:space:]]*//p' | head -1)"

echo "Image:        $IMAGE"
echo "Network:      $NETWORK"
echo "Container IP: $CONTAINER_IP"
echo "Running:      $RUNNING"

[[ "$RUNNING" == true ]] || fail 'Bambuddy container is not running'
[[ "$NETWORK" == umbrel_main_network ]] || fail "expected umbrel_main_network, got $NETWORK"
[[ -n "$CONTAINER_IP" ]] || fail 'could not read container IP'
[[ "$CONTAINER_IP" == "$BIND_IP" ]] || fail "expected container IP $BIND_IP, got $CONTAINER_IP"
[[ -n "$COMPOSE_IMAGE" ]] || fail 'could not read server image from compose'
[[ "$IMAGE" == "$COMPOSE_IMAGE" ]] || fail "running image does not match compose: $IMAGE != $COMPOSE_IMAGE"

! grep -Eq '^[[:space:]]*network_mode:[[:space:]]*host([[:space:]]|$)' "$COMPOSE" || fail 'compose uses host networking'
grep -Fq 'APP_HOST: server' "$COMPOSE" || fail 'compose APP_HOST changed'
grep -Fq "ipv4_address: $BIND_IP" "$COMPOSE" || fail 'compose static container IP changed'
grep -Fq 'name: umbrel_main_network' "$COMPOSE" || fail 'compose network name changed'
grep -Fq "VIRTUAL_PRINTER_ADVERTISE_ADDRESS: $HOST_IP" "$COMPOSE" || fail 'Virtual Printer advertise address changed'
grep -Fq "VIRTUAL_PRINTER_PASV_ADDRESS: $HOST_IP" "$COMPOSE" || fail 'Virtual Printer PASV address changed'
grep -Fq 'NET_BIND_SERVICE' "$COMPOSE" || fail 'NET_BIND_SERVICE capability missing'
! grep -Eq 'bambuddy_lan|bambuddy_bridge|192\.168\.0\.200|NET_ADMIN|post_start:|^[[:space:]]*entrypoint:' "$COMPOSE" || fail 'obsolete host/ipvlan compose settings are still present'

for port in 21 322 990 3000 3002 6000 8883 2024-2026 50000-50100; do
  grep -Fq "\"$port:$port\"" "$COMPOSE" || fail "Virtual Printer port $port is not published"
done

echo 'Virtual Printer compose invariants: PASS'

echo
echo '=========================================='
echo ' HEALTH / UMBREL PROXY'
echo '=========================================='

curl -fsS "http://$CONTAINER_IP:8000/health"
printf '\n'
curl -fsS "http://127.0.0.1:$APP_PORT/health" >/dev/null

echo 'Container health: PASS'
echo 'Umbrel app gateway health: PASS'
echo "LAN clients should use http://$HOST_IP:$APP_PORT (nftables redirect is not testable from localhost)."

echo
echo '=========================================='
echo ' PUBLISHED VIRTUAL PRINTER PORTS'
echo '=========================================='

python3 - <<'PY'
import socket

failed = False
for port, name in [
    (21, 'FTP control'),
    (322, 'RTSPS/camera'),
    (990, 'FTPS'),
    (3000, 'VP bind 3000'),
    (3002, 'VP bind 3002'),
    (6000, 'LiveView/camera'),
    (8883, 'MQTT TLS'),
    (2024, 'Camera/aux'),
    (50000, 'FTP data'),
]:
    sock = socket.socket()
    sock.settimeout(5)
    try:
        sock.connect(('127.0.0.1', port))
        print(f'127.0.0.1:{port:<5} {name:<18} OPEN')
    except Exception as exc:
        failed = True
        print(f'127.0.0.1:{port:<5} {name:<18} FAIL ({type(exc).__name__}: {exc})')
    finally:
        sock.close()
if failed:
    raise SystemExit(1)
PY

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

python3 - "$CONTAINER_IP" "$X2D_IP" "$HOST_IP" <<'PY'
import json
import sys
import urllib.error
import urllib.request

container_ip, x2d_ip, host_ip = sys.argv[1:4]
base = f"http://{container_ip}:8000/api/v1"


def get(path):
    try:
        with urllib.request.urlopen(base + path, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            raise SystemExit(
                f"API verification requires Bambuddy authentication ({exc.code}); "
                "verify X2D/AMS/Spoolman/Virtual Printer in the UI instead"
            )
        raise


printers = get("/printers/")
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
regular_ams_trays = 0
for unit in ams:
    if not isinstance(unit, dict):
        continue
    trays = unit.get("tray") or unit.get("trays") or []
    is_ht = bool(unit.get("is_ams_ht"))
    if not is_ht:
        regular_ams_trays += len(trays)
    print(
        f"  AMS id={unit.get('id')} humidity={unit.get('humidity')} "
        f"temp={unit.get('temp')} is_ams_ht={is_ht} trays={len(trays)}"
    )
    for tray in trays:
        if isinstance(tray, dict):
            print(
                "    tray="
                f"{tray.get('id')} type={tray.get('tray_type')} "
                f"color={tray.get('tray_color')} remain={tray.get('remain')} "
                f"exists={tray.get('exists')}"
            )

vt_trays = status.get("vt_tray") or []
print(f"Virtual/external trays: {len(vt_trays)}")
for tray in vt_trays:
    if isinstance(tray, dict):
        print(
            "  vt_tray="
            f"{tray.get('id')} type={tray.get('tray_type')} "
            f"color={tray.get('tray_color')} remain={tray.get('remain')} "
            f"exists={tray.get('exists')}"
        )

if not status.get("connected"):
    raise SystemExit("X2D is not connected in Bambuddy")
if not status.get("ams_exists") or not ams:
    raise SystemExit("AMS 2 Pro telemetry is missing")
if regular_ams_trays < 4:
    raise SystemExit(f"AMS 2 Pro tray telemetry incomplete: expected at least 4 tray records, got {regular_ams_trays}")

diagnostic = get(f"/printers/{pid}/diagnostic")
checks = {check.get("id"): check.get("status") for check in diagnostic.get("checks", []) if isinstance(check, dict)}
print(f"Printer diagnostic: overall={diagnostic.get('overall')} developer_mode={checks.get('developer_mode')} network_mode={checks.get('network_mode')}")
if checks.get("developer_mode") != "pass":
    raise SystemExit("Developer Mode diagnostic did not pass")
if diagnostic.get("overall") == "fail":
    raise SystemExit("Printer diagnostic failed")

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
        f"remote_interface_ip={item.get('remote_interface_ip')} "
        f"running={runtime.get('running')} pending_files={runtime.get('pending_files')}"
    )

enabled_vps = [v for v in vps if isinstance(v, dict) and v.get("enabled")]
if enabled_vps:
    for item in enabled_vps:
        if item.get("bind_ip") != container_ip:
            raise SystemExit(f"VP {item.get('id')} bind_ip is {item.get('bind_ip')}, expected {container_ip}")
        if item.get("remote_interface_ip") != host_ip:
            raise SystemExit(
                f"VP {item.get('id')} remote_interface_ip is {item.get('remote_interface_ip')}, expected {host_ip}"
            )
        runtime = item.get("status") or {}
        if not runtime.get("running"):
            raise SystemExit(f"VP {item.get('id')} is enabled but not running")
        proxy = runtime.get("proxy") or {}
        if not proxy.get("running"):
            raise SystemExit(f"VP {item.get('id')} proxy is not running")
        vp_diagnostic = get(f"/virtual-printers/{item.get('id')}/diagnostic")
        print(
            f"  VP diagnostic id={item.get('id')} "
            f"overall={vp_diagnostic.get('overall')} "
            f"bind_interface={next((c.get('status') for c in vp_diagnostic.get('checks', []) if c.get('id') == 'bind_interface'), None)}"
        )
        if vp_diagnostic.get("overall") != "ok":
            raise SystemExit(f"VP {item.get('id')} diagnostic is {vp_diagnostic.get('overall')}")
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
echo "CONTAINER_IP=$CONTAINER_IP"
echo 'This script is read-only; no containers, database rows, or settings were changed.'
