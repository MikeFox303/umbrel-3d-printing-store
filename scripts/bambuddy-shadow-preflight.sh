#!/usr/bin/env bash
set -euo pipefail

OFFICIAL_IMAGE='ghcr.io/maziggy/bambuddy:1.2.5.5@sha256:dc627d618cc3d3252ae4ab33af74c4679c66a9a06e0e3bbb7aefa32d1a4d4a07'
ROLLBACK_IMAGE='ghcr.io/mikefox303/bambuddy:1.2.5.5-x2d.204@sha256:0539eb76a64994081a868a30cb854097a0e9a9732dc0d60f05666748fe341743'
SOURCE_DATA="${1:-/home/umbrel/umbrel/app-data/my3d-bambuddy/data}"
SHADOW_ROOT="${2:-/tmp/bambuddy-official-shadow}"
SHADOW_PORT="${SHADOW_PORT:-18280}"
ROLLBACK_PORT="${ROLLBACK_PORT:-18281}"
NETWORK='bambuddy-official-shadow-net'
CONTAINER='bambuddy-official-shadow'
ROLLBACK_CONTAINER='bambuddy-rollback-shadow'

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v python3 >/dev/null || fail 'python3 is required'
command -v docker >/dev/null || fail 'docker is required'
[[ -d "$SOURCE_DATA" ]] || fail "source data directory not found: $SOURCE_DATA"
[[ -f "$SOURCE_DATA/bambuddy.db" ]] || fail "source DB not found: $SOURCE_DATA/bambuddy.db"

SOURCE_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SOURCE_DATA")"
SHADOW_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SHADOW_ROOT")"
case "$SHADOW_REAL/" in
  "$SOURCE_REAL/"*|"${SOURCE_REAL%/}") fail 'shadow path must not be inside production data' ;;
esac
case "$SOURCE_REAL/" in
  "$SHADOW_REAL/"*) fail 'production data must not be inside shadow path' ;;
esac

cleanup_runtime() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker rm -f "$ROLLBACK_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup_runtime EXIT
cleanup_runtime

rm -rf "$SHADOW_ROOT"
mkdir -p "$SHADOW_ROOT/data" "$SHADOW_ROOT/logs" "$SHADOW_ROOT/rollback-data" "$SHADOW_ROOT/rollback-logs"
chmod 700 "$SHADOW_ROOT"

echo '== Copying non-database data and taking an online SQLite backup =='
python3 - "$SOURCE_DATA" "$SHADOW_ROOT/data" <<'PY'
import os
import shutil
import sqlite3
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
excluded = {"bambuddy.db", "bambuddy.db-wal", "bambuddy.db-shm", "bambutrack.db", "bambutrack.db-wal", "bambutrack.db-shm"}
for entry in src.iterdir():
    if entry.name in excluded:
        continue
    target = dst / entry.name
    if entry.is_dir():
        shutil.copytree(entry, target, symlinks=True, dirs_exist_ok=True)
    elif entry.is_symlink():
        target.symlink_to(os.readlink(entry))
    else:
        shutil.copy2(entry, target)

source_db = sqlite3.connect(f"file:{src / 'bambuddy.db'}?mode=ro", uri=True)
target_db = sqlite3.connect(dst / "bambuddy.db")
with target_db:
    source_db.backup(target_db)
check = target_db.execute("PRAGMA quick_check").fetchone()[0]
if check != "ok":
    raise SystemExit(f"shadow backup quick_check failed: {check}")
print("source user_version:", source_db.execute("PRAGMA user_version").fetchone()[0])
print("shadow user_version:", target_db.execute("PRAGMA user_version").fetchone()[0])
print("shadow tables:", target_db.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0])
source_db.close()
target_db.close()
PY
cp "$SHADOW_ROOT/data/bambuddy.db" "$SHADOW_ROOT/bambuddy-before-upstream.db"

# A temporary internal bridge is deliberately NOT umbrel_main_network. It gives the
# shadow container a unique host port while preventing egress to X2D and Spoolman.
docker network create --internal "$NETWORK" >/dev/null

echo '== Pulling official immutable image anonymously =='
docker pull "$OFFICIAL_IMAGE"

echo '== Starting official upstream against the DB copy =='
docker run -d \
  --name "$CONTAINER" \
  --network "$NETWORK" \
  -p "127.0.0.1:${SHADOW_PORT}:8000" \
  -e TZ=Europe/Kyiv \
  -e PUID=1000 \
  -e PGID=1000 \
  -e PORT=8000 \
  -v "$SHADOW_ROOT/data:/app/data" \
  -v "$SHADOW_ROOT/logs:/app/logs" \
  "$OFFICIAL_IMAGE" >/dev/null

healthy=false
for _ in $(seq 1 120); do
  if curl --fail --silent --show-error "http://127.0.0.1:${SHADOW_PORT}/health" >/dev/null 2>&1; then
    healthy=true
    break
  fi
  if docker exec "$CONTAINER" python -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=2)' >/dev/null 2>&1; then
    healthy=true
    break
  fi
  [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER")" == true ]] || break
  sleep 1
done

docker logs "$CONTAINER" >"$SHADOW_ROOT/official-container.log" 2>&1 || true
[[ "$healthy" == true ]] || {
  cat "$SHADOW_ROOT/official-container.log" >&2
  fail 'official upstream failed shadow startup/health'
}

docker stop -t 10 "$CONTAINER" >/dev/null
exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$CONTAINER")"
[[ "$exit_code" == 0 ]] || fail "official container did not stop cleanly (exit=$exit_code)"
docker rm "$CONTAINER" >/dev/null

echo '== Validating migrated shadow DB =='
python3 - "$SHADOW_ROOT/data/bambuddy.db" <<'PY'
import sqlite3
import sys
from pathlib import Path
p = Path(sys.argv[1])
db = sqlite3.connect(p)
check = db.execute("PRAGMA quick_check").fetchone()[0]
if check != "ok":
    raise SystemExit(f"post-migration quick_check failed: {check}")
print("post-migration user_version:", db.execute("PRAGMA user_version").fetchone()[0])
print("post-migration tables:", db.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0])
db.close()
PY

# Rollback compatibility is checked on a SECOND copy of the migrated shadow data.
# Production data is never mounted into either container.
echo '== Checking old production image against migrated DB copy =='
cp -a "$SHADOW_ROOT/data/." "$SHADOW_ROOT/rollback-data/"
if ! docker pull "$ROLLBACK_IMAGE"; then
  docker image inspect "$ROLLBACK_IMAGE" >/dev/null || fail 'rollback image is neither pullable nor present locally'
fi

docker run -d \
  --name "$ROLLBACK_CONTAINER" \
  --network "$NETWORK" \
  -p "127.0.0.1:${ROLLBACK_PORT}:8000" \
  -e TZ=Europe/Kyiv \
  -e PUID=1000 \
  -e PGID=1000 \
  -e PORT=8000 \
  -v "$SHADOW_ROOT/rollback-data:/app/data" \
  -v "$SHADOW_ROOT/rollback-logs:/app/logs" \
  "$ROLLBACK_IMAGE" >/dev/null

rollback_healthy=false
for _ in $(seq 1 120); do
  if curl --fail --silent --show-error "http://127.0.0.1:${ROLLBACK_PORT}/health" >/dev/null 2>&1; then
    rollback_healthy=true
    break
  fi
  if docker exec "$ROLLBACK_CONTAINER" python -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=2)' >/dev/null 2>&1; then
    rollback_healthy=true
    break
  fi
  [[ "$(docker inspect --format '{{.State.Running}}' "$ROLLBACK_CONTAINER")" == true ]] || break
  sleep 1
done

docker logs "$ROLLBACK_CONTAINER" >"$SHADOW_ROOT/rollback-container.log" 2>&1 || true
[[ "$rollback_healthy" == true ]] || {
  cat "$SHADOW_ROOT/rollback-container.log" >&2
  fail 'rollback image is not compatible with the migrated shadow DB; production upgrade must remain blocked'
}
docker stop -t 10 "$ROLLBACK_CONTAINER" >/dev/null
rollback_exit="$(docker inspect --format '{{.State.ExitCode}}' "$ROLLBACK_CONTAINER")"
[[ "$rollback_exit" == 0 ]] || fail "rollback container did not stop cleanly (exit=$rollback_exit)"
docker rm "$ROLLBACK_CONTAINER" >/dev/null

echo
echo 'SHADOW_PREFLIGHT=PASS'
echo "OFFICIAL_IMAGE=$OFFICIAL_IMAGE"
echo "ROLLBACK_IMAGE=$ROLLBACK_IMAGE"
echo "SHADOW_ROOT=$SHADOW_ROOT"
echo "OFFICIAL_EXIT_CODE=$exit_code"
echo "ROLLBACK_EXIT_CODE=$rollback_exit"
echo 'Production DB was never mounted into a test container.'
