#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backup_dir="$script_dir/../backups"
mkdir -p "$backup_dir"
old_ids=( $(docker ps -aq --filter 'ancestor=ghcr.io/fire-devils/filaman-system') )
(( ${#old_ids[@]} == 1 )) || { echo 'Expected exactly one old FilaMan container.' >&2; exit 1; }
old_id="${old_ids[0]}"
[[ "$(docker inspect --format '{{.State.Running}}' "$old_id")" == 'false' ]] || { echo 'Stop Dockge FilaMan first.' >&2; exit 1; }
new_id="$(docker ps -aq --filter 'name=^/my3d-filaman_server_1$')"
[[ -n "$new_id" ]] || { echo 'Install the Umbrel app once so its stopped container exists.' >&2; exit 1; }
[[ "$(docker inspect --format '{{.State.Running}}' "$new_id")" == 'false' ]] || { echo 'Stop the Umbrel app first.' >&2; exit 1; }
old_source="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Source}}{{end}}{{end}}' "$old_id")"
new_source="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Source}}{{end}}{{end}}' "$new_id")"
[[ -n "$old_source" && -n "$new_source" ]] || { echo 'Could not resolve /app/data mounts.' >&2; exit 1; }
latest_backup="$(find "$backup_dir" -maxdepth 1 -name 'filaman-data-*.tar.gz' -type f -size +0c -print -quit)"
[[ -n "$latest_backup" ]] || { echo 'Run backup-dockge-filaman.sh successfully before migration.' >&2; exit 1; }
mkdir -p "$new_source"
if [[ -n "$(find "$new_source" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then tar -C "$new_source" -czf "$backup_dir/umbrel-destination-$(date +%Y-%m-%d_%H%M%S).tar.gz" .; fi
docker run --rm -v "$old_source:/source:ro" -v "$new_source:/destination" alpine:3.20 sh -c 'cd /source && tar -cf - . | tar -C /destination -xpf -'
[[ -f "$new_source/filaman.db" ]] || { echo 'Migration copy did not produce filaman.db.' >&2; exit 1; }
docker start "$new_id" >/dev/null
for _ in $(seq 1 12); do
  if docker exec "$new_id" python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"; then
    echo 'Migration successful. Keep Dockge stopped; do not remove its volume or backups.'
    exit 0
  fi
  sleep 5
done
echo 'New app is unhealthy. Stop it and start the unchanged Dockge stack to roll back.' >&2
exit 1
