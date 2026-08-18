#!/usr/bin/env bash
set -euo pipefail

image='ghcr.io/fire-devils/filaman-system'
containers=()
while IFS= read -r id; do [[ -n "$id" ]] && containers+=("$id"); done < <(docker ps -aq --filter "ancestor=$image")
(( ${#containers[@]} == 1 )) || { echo "Expected one Dockge FilaMan container; found ${#containers[@]}." >&2; exit 1; }
container="${containers[0]}"
[[ "$(docker inspect --format '{{.State.Running}}' "$container")" == 'false' ]] || { echo "Stop FilaMan before backup: $container" >&2; exit 1; }
mount="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Type}}|{{.Name}}|{{.Source}}{{end}}{{end}}' "$container")"
IFS='|' read -r mount_type volume_name source <<< "$mount"
[[ -n "${source:-}" ]] || { echo 'Could not locate /app/data.' >&2; exit 1; }

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backup_dir="$script_dir/../backups"
mkdir -p "$backup_dir"
archive="$backup_dir/filaman-data-$(date +%Y-%m-%d_%H%M%S).tar.gz"
echo "Container: $container; mount: $mount_type; source: $source"
if [[ "$mount_type" == 'volume' ]]; then
  docker run --rm -v "$volume_name:/source:ro" -v "$backup_dir:/backup" alpine:3.20 sh -c "tar -C /source -czf /backup/$(basename "$archive") ."
else
  tar -C "$source" -czf "$archive" .
fi
[[ -s "$archive" ]] || { echo 'Backup archive is empty.' >&2; exit 1; }
tar -tzf "$archive" | grep -qx 'filaman.db' || echo 'Warning: filaman.db was not found in the archive.' >&2
echo "Size: $(du -h "$archive" | awk '{print $1}')"
sha256sum "$archive"
