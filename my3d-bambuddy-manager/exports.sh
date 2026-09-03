#!/usr/bin/env bash
set -euo pipefail

# New Bambuddy packages export the actual definition/data paths before this
# file is sourced. Keep older installed Bambuddy packages usable by deriving
# the sibling app directory from Manager's own documented EXPORTS_APP_DIR.
if [[ -z "${APP_BAMBUDDY_APP_DIR:-}" ]]; then
  export APP_BAMBUDDY_APP_DIR="$(dirname "${EXPORTS_APP_DIR}")/my3d-bambuddy"
fi

# Older packages used the standard app-data/data location. If Bambuddy has a
# relocated data root, its newer dependency export above wins instead.
if [[ -z "${APP_BAMBUDDY_DATA_DIR:-}" ]]; then
  export APP_BAMBUDDY_DATA_DIR="${APP_BAMBUDDY_APP_DIR}/data"
fi
