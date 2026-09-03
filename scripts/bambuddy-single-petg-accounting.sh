#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
AMS_ID="${2:-0}"
TRAY_ID="${3:-0}"
APP_DIR="${APP_DIR:-/home/umbrel/umbrel/app-data/my3d-bambuddy}"
DB="$APP_DIR/data/bambuddy.db"
SERVER='my3d-bambuddy_server_1'
X2D_IP="${X2D_IP:-192.168.0.151}"
STATE_FILE="${STATE_FILE:-/tmp/bambuddy-single-petg-accounting.json}"
EXPECTED_IMAGE='ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:dc627d618cc3d3252ae4ab33af74c4679c66a9a06e0e3bbb7aefa32d1a4d4a07'

fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"; }

[[ "$MODE" == before || "$MODE" == after ]] || {
  echo "Usage: $0 before [ams_id] [tray_id]"
  echo "       $0 after"
  exit 2
}

for cmd in docker python3 curl; do need "$cmd"; done
[[ -f "$DB" ]] || fail "database not found: $DB"

IMAGE="$(docker inspect "$SERVER" --format '{{.Config.Image}}')"
NETWORK="$(docker inspect "$SERVER" --format '{{.HostConfig.NetworkMode}}')"
RUNNING="$(docker inspect "$SERVER" --format '{{.State.Running}}')"
[[ "$IMAGE" == "$EXPECTED_IMAGE" ]] || fail "unexpected Bambuddy image: $IMAGE"
[[ "$NETWORK" == host ]] || fail "Bambuddy is not using host networking"
[[ "$RUNNING" == true ]] || fail "Bambuddy is not running"
curl -fsS http://127.0.0.1:8000/health >/dev/null
curl -fsS http://127.0.0.1:7912/api/v1/health >/dev/null

python3 - "$MODE" "$AMS_ID" "$TRAY_ID" "$DB" "$STATE_FILE" "$X2D_IP" <<'PY'
import datetime as dt
import json
import math
import sqlite3
import sys
import urllib.error
import urllib.request
from pathlib import Path

mode = sys.argv[1]
ams_id = int(sys.argv[2])
tray_id = int(sys.argv[3])
db_path = sys.argv[4]
state_path = Path(sys.argv[5])
x2d_ip = sys.argv[6]

BAMBUDDY = "http://127.0.0.1:8000/api/v1"
SPOOLMAN = "http://127.0.0.1:7912/api/v1"
ACTIVE = {"RUNNING", "PAUSE", "PREPARE", "SLICING"}
EPS = 0.05


def get_json(url):
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"HTTP {exc.code} for {url}: {body[:300]}") from exc
    except Exception as exc:
        raise SystemExit(f"GET failed for {url}: {type(exc).__name__}: {exc}") from exc


def bambuddy(path):
    return get_json(BAMBUDDY + path)


def spoolman_spool(spool_id):
    return get_json(f"{SPOOLMAN}/spool/{int(spool_id)}")


def normalize_printers(value):
    if isinstance(value, dict):
        for key in ("items", "printers", "data"):
            if isinstance(value.get(key), list):
                return value[key]
    return value if isinstance(value, list) else []


def live_context():
    printers = normalize_printers(bambuddy("/printers/"))
    x2d = next((p for p in printers if isinstance(p, dict) and p.get("ip_address") == x2d_ip), None)
    if not x2d:
        raise SystemExit(f"X2D {x2d_ip} not found in Bambuddy API")
    status = bambuddy(f"/printers/{x2d['id']}/status")
    state = str(status.get("state") or "").upper()
    print(f"X2D connected={status.get('connected')} state={state}")
    if not status.get("connected"):
        raise SystemExit("X2D is not connected")
    if state in ACTIVE:
        raise SystemExit(f"acceptance step blocked: X2D is active ({state})")

    vps_value = bambuddy("/virtual-printers")
    vps = vps_value.get("printers", []) if isinstance(vps_value, dict) else []
    enabled = [v for v in vps if isinstance(v, dict) and v.get("enabled")]
    if not enabled:
        raise SystemExit("no enabled Virtual Printer found")
    running_queue = []
    for vp in enabled:
        runtime = vp.get("status") or {}
        print(
            f"VP id={vp.get('id')} name={vp.get('name')} mode={vp.get('mode')} "
            f"auto_dispatch={vp.get('auto_dispatch')} running={runtime.get('running')}"
        )
        if vp.get("mode") == "queue" and runtime.get("running"):
            running_queue.append(vp)
    if not running_queue:
        raise SystemExit("enabled Print Queue Virtual Printer is not running")
    return x2d, status, running_queue[0]


def db_snapshot(printer_id):
    with sqlite3.connect(db_path) as db:
        assignments = db.execute(
            "SELECT printer_id, ams_id, tray_id, spoolman_spool_id "
            "FROM spoolman_slot_assignments WHERE printer_id=? "
            "ORDER BY ams_id, tray_id",
            (printer_id,),
        ).fetchall()
        max_log_id = db.execute(
            "SELECT COALESCE(MAX(id),0) FROM print_log_entries WHERE printer_id=?",
            (printer_id,),
        ).fetchone()[0]
        max_queue_id = db.execute("SELECT COALESCE(MAX(id),0) FROM print_queue").fetchone()[0]
    return assignments, int(max_log_id), int(max_queue_id)


def weights_for(assignments):
    result = {}
    seen = set()
    for _printer_id, a, t, spool_id in assignments:
        spool_id = int(spool_id)
        if spool_id in seen:
            continue
        seen.add(spool_id)
        spool = spoolman_spool(spool_id)
        filament = spool.get("filament") or {}
        result[str(spool_id)] = {
            "id": spool_id,
            "remaining_weight": spool.get("remaining_weight"),
            "used_weight": spool.get("used_weight"),
            "filament_id": filament.get("id"),
            "filament_name": filament.get("name"),
            "material": filament.get("material"),
            "color_hex": filament.get("color_hex"),
        }
    return result


def fnum(value):
    return None if value is None else float(value)


def positive_delta(before, after):
    b_used, a_used = fnum(before.get("used_weight")), fnum(after.get("used_weight"))
    b_rem, a_rem = fnum(before.get("remaining_weight")), fnum(after.get("remaining_weight"))
    used_delta = None if b_used is None or a_used is None else a_used - b_used
    remaining_delta = None if b_rem is None or a_rem is None else b_rem - a_rem
    candidates = [d for d in (used_delta, remaining_delta) if d is not None and d > EPS]
    effective = max(candidates) if candidates else 0.0
    return used_delta, remaining_delta, effective


x2d, status, vp = live_context()
printer_id = int(x2d["id"])
assignments, max_log_id, max_queue_id = db_snapshot(printer_id)
if not assignments:
    raise SystemExit("no Spoolman slot assignments found for X2D")

if mode == "before":
    target = [r for r in assignments if int(r[1]) == ams_id and int(r[2]) == tray_id]
    if len(target) != 1:
        raise SystemExit(f"expected exactly one assignment for AMS {ams_id} tray {tray_id}, found {len(target)}")
    expected_spool = int(target[0][3])

    ams_units = status.get("ams") or []
    telemetry_tray = None
    for unit in ams_units:
        if not isinstance(unit, dict) or int(unit.get("id", -999)) != ams_id:
            continue
        for tray in unit.get("tray") or []:
            if isinstance(tray, dict) and int(tray.get("id", -999)) == tray_id:
                telemetry_tray = tray
                break
    if telemetry_tray is None:
        raise SystemExit(f"AMS telemetry does not contain AMS {ams_id} tray {tray_id}")
    material = str(telemetry_tray.get("tray_type") or "").upper()
    exists = telemetry_tray.get("exists")
    print(
        f"Target AMS={ams_id} tray={tray_id} material={material} exists={exists} "
        f"Spoolman spool={expected_spool}"
    )
    if "PETG" not in material:
        raise SystemExit(f"target slot is not PETG: {material!r}")
    if exists is False:
        raise SystemExit("target PETG slot reports no physical spool")

    weights = weights_for(assignments)
    state = {
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "printer_id": printer_id,
        "printer_ip": x2d_ip,
        "vp_id": vp.get("id"),
        "vp_name": vp.get("name"),
        "vp_auto_dispatch": vp.get("auto_dispatch"),
        "ams_id": ams_id,
        "tray_id": tray_id,
        "expected_spool_id": expected_spool,
        "assignments": [list(map(int, r)) for r in assignments],
        "max_print_log_id": max_log_id,
        "max_queue_id": max_queue_id,
        "spools": weights,
    }
    state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n")
    state_path.chmod(0o600)

    print("\nSpoolman baseline:")
    for spool_id, spool in weights.items():
        marker = "  <== TARGET" if int(spool_id) == expected_spool else ""
        print(
            f"  spool={spool_id} material={spool.get('material')} "
            f"remaining={spool.get('remaining_weight')} used={spool.get('used_weight')}{marker}"
        )
    print(f"Baseline max print_log id: {max_log_id}")
    print(f"Baseline max queue id: {max_queue_id}")
    print(f"STATE_FILE={state_path}")
    print("SINGLE_PETG_BASELINE=PASS")
    print("\nNEXT:")
    print("1) In Bambu Studio select X2D Virtual.")
    print("2) Slice ONE small single-material PETG model using AMS A1 / slot 0.")
    print("3) Use Send, NOT Print.")
    if vp.get("auto_dispatch"):
        print("4) Auto-dispatch is enabled: the queued job should start when X2D is available.")
    else:
        print("4) Auto-dispatch is disabled: open Bambuddy Queue and manually Start the new job.")
    print("5) Let the print finish completely, then run this script with: after")
    raise SystemExit(0)

if not state_path.exists():
    raise SystemExit(f"baseline state not found: {state_path}; run 'before' first")
state = json.loads(state_path.read_text())
if int(state.get("printer_id")) != printer_id:
    raise SystemExit("printer id changed since baseline")
expected_spool = int(state["expected_spool_id"])
baseline_assignments = [tuple(map(int, row)) for row in state["assignments"]]
if assignments != baseline_assignments:
    print("Before assignments:", baseline_assignments)
    print("After assignments:", assignments)
    raise SystemExit("Spoolman slot assignments changed during print acceptance test")

before_weights = state["spools"]
after_weights = weights_for(assignments)
print("\nSpoolman deltas:")
changed = []
for spool_id in sorted(before_weights, key=lambda x: int(x)):
    before = before_weights[spool_id]
    after = after_weights.get(spool_id)
    if after is None:
        raise SystemExit(f"spool {spool_id} disappeared from Spoolman")
    used_delta, remaining_delta, effective = positive_delta(before, after)
    print(
        f"  spool={spool_id} used_delta={used_delta} "
        f"remaining_delta={remaining_delta} effective={effective:.3f}g"
    )
    if effective > EPS:
        changed.append((int(spool_id), effective, used_delta, remaining_delta))

expected_changes = [row for row in changed if row[0] == expected_spool]
other_changes = [row for row in changed if row[0] != expected_spool]
if len(expected_changes) != 1:
    raise SystemExit(
        f"expected Spoolman spool {expected_spool} to be debited exactly once; "
        f"changed spools={changed}"
    )
if other_changes:
    raise SystemExit(f"unexpected other assigned spools changed: {other_changes}")
spool_delta = float(expected_changes[0][1])

baseline_log_id = int(state["max_print_log_id"])
baseline_queue_id = int(state["max_queue_id"])
with sqlite3.connect(db_path) as db:
    db.row_factory = sqlite3.Row
    logs = db.execute(
        "SELECT id, queue_item_id, archive_id, print_name, status, filament_used_grams, "
        "started_at, completed_at FROM print_log_entries "
        "WHERE printer_id=? AND id>? ORDER BY id",
        (printer_id, baseline_log_id),
    ).fetchall()

completed = [row for row in logs if str(row["status"] or "").lower() == "completed"]
print(f"New print-log rows since baseline: {len(logs)}; completed={len(completed)}")
for row in logs:
    print(
        f"  log_id={row['id']} queue_item_id={row['queue_item_id']} "
        f"status={row['status']} grams={row['filament_used_grams']} name={row['print_name']}"
    )
if len(completed) != 1:
    raise SystemExit("expected exactly one completed X2D print since baseline; test is ambiguous")
log = completed[0]
queue_item_id = log["queue_item_id"]
if queue_item_id is None:
    raise SystemExit("completed print has no queue_item_id; cannot prove Virtual Printer queue dispatch")
if int(queue_item_id) <= baseline_queue_id:
    raise SystemExit(
        f"queue_item_id {queue_item_id} is not newer than baseline max queue id {baseline_queue_id}"
    )
log_grams = fnum(log["filament_used_grams"])
if log_grams is None or log_grams <= EPS:
    raise SystemExit("completed print log has no usable filament_used_grams value")

with sqlite3.connect(db_path) as db:
    db.row_factory = sqlite3.Row
    queue_row = db.execute(
        "SELECT id, printer_id, archive_id, status FROM print_queue WHERE id=?",
        (int(queue_item_id),),
    ).fetchone()
if queue_row is None:
    raise SystemExit(f"queue item {queue_item_id} referenced by print log no longer exists")
print(
    f"Queue evidence: id={queue_row['id']} printer_id={queue_row['printer_id']} "
    f"archive_id={queue_row['archive_id']} status={queue_row['status']}"
)

# The same 3MF-derived usage feeds the authoritative print log and the Spoolman
# completion report for a normal single-material queue print. Allow small float
# / API rounding, but reject a missing debit or anything remotely like 2x usage.
tolerance = max(0.50, log_grams * 0.08)
diff = abs(spool_delta - log_grams)
ratio = spool_delta / log_grams
print(
    f"Accounting comparison: Spoolman delta={spool_delta:.3f}g "
    f"PrintLog={log_grams:.3f}g diff={diff:.3f}g ratio={ratio:.3f} tolerance={tolerance:.3f}g"
)
if diff > tolerance:
    raise SystemExit(
        "Spoolman debit does not match Bambuddy print-log usage within tolerance; "
        "possible attribution/double-debit problem"
    )
if ratio >= 1.50:
    raise SystemExit("Spoolman debit is >=1.5x print-log usage; possible double debit")

print("\nVP_QUEUE_DISPATCH=PASS")
print("SINGLE_PETG_SPOOL_ATTRIBUTION=PASS")
print("SINGLE_PETG_NO_DOUBLE_DEBIT=PASS")
print("SINGLE_PETG_ACCOUNTING=PASS")
print(f"EXPECTED_SPOOL_ID={expected_spool}")
print(f"SPOOLMAN_DELTA_G={spool_delta:.3f}")
print(f"PRINT_LOG_G={log_grams:.3f}")
print(f"QUEUE_ITEM_ID={queue_item_id}")
print(f"PRINT_LOG_ID={log['id']}")
print(f"STATE_FILE={state_path}")
PY
