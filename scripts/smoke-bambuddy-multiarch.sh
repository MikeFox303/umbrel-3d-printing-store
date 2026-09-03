#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <multiarch-image@digest> <expected-app-version> <container-name> <host-port>" >&2
  exit 2
fi

IMAGE="$1"
EXPECTED_APP_VERSION="$2"
CONTAINER_NAME="$3"
HOST_PORT="$4"
REPOSITORY='ghcr.io/maziggy/bambuddy'

if [[ ! "$IMAGE" =~ ^ghcr\.io/maziggy/bambuddy:[^@[:space:]]+@sha256:[0-9a-f]{64}$ ]]; then
  echo "Refusing non-immutable or non-official Bambuddy image: $IMAGE" >&2
  exit 2
fi
if [[ ! "$HOST_PORT" =~ ^[0-9]+$ ]]; then
  echo "Invalid host port: $HOST_PORT" >&2
  exit 2
fi

INDEX_RAW="$(docker buildx imagetools inspect --raw "$IMAGE")"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for platform in linux/amd64 linux/arm64; do
  cleanup
  arch="${platform##*/}"
  child_digest="$(jq -er --arg arch "$arch" '
    [ .manifests[]
      | select(.platform.os == "linux" and .platform.architecture == $arch)
      | .digest
    ]
    | if length == 1 then .[0] else error("expected exactly one child manifest") end
  ' <<<"$INDEX_RAW")"
  if [[ ! "$child_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Invalid ${platform} child digest: $child_digest" >&2
    exit 1
  fi

  platform_image="${REPOSITORY}@${child_digest}"
  root="/tmp/${CONTAINER_NAME}-${arch}"
  rm -rf "$root"
  mkdir -p "$root/data" "$root/logs"

  echo "Smoke-testing ${platform} via child manifest ${child_digest}"
  docker pull --platform "$platform" "$platform_image"
  docker run --platform "$platform" -d \
    --name "$CONTAINER_NAME" \
    -p "127.0.0.1:${HOST_PORT}:8000" \
    -e TZ=UTC \
    -e PUID=1000 \
    -e PGID=1000 \
    -e PORT=8000 \
    -v "$root/data:/app/data" \
    -v "$root/logs:/app/logs" \
    "$platform_image"

  healthy=false
  for attempt in $(seq 1 120); do
    if curl --fail --silent --show-error "http://127.0.0.1:${HOST_PORT}/health" >/dev/null 2>&1; then
      healthy=true
      break
    fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" != true ]]; then
      break
    fi
    sleep 1
  done

  if [[ "$healthy" != true ]]; then
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi

  actual_app_version="$(docker exec "$CONTAINER_NAME" python -c 'from backend.app.core.config import APP_VERSION; print(APP_VERSION)')"
  if [[ "$actual_app_version" != "$EXPECTED_APP_VERSION" ]]; then
    echo "Refusing mismatched Bambuddy image: expected ${EXPECTED_APP_VERSION}, image reports ${actual_app_version}" >&2
    exit 1
  fi

  test -f "$root/data/bambuddy.db"
  docker rm -f "$CONTAINER_NAME" >/dev/null

done
