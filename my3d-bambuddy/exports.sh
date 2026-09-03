#!/usr/bin/env bash
set -euo pipefail

# Dependency path contract for companion apps such as Bambuddy Manager.
# Umbrel sets these to the app definition directory and the current physical
# persistent data root, including when app data is relocated to other storage.
export APP_BAMBUDDY_APP_DIR="${EXPORTS_APP_DIR}"
export APP_BAMBUDDY_DATA_DIR="${EXPORTS_APP_DATA_DIR}"
