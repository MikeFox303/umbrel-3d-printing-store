#!/usr/bin/env bash
set -euo pipefail

# New Bambuddy packages export the actual definition/data paths before this
# file is sourced. Keep older installed Bambuddy packages usable by deriving
# the sibling app directory from Manager's own documented EXPORTS_APP_DIR.
if [[ -z "${APP_BAMBUDDY_APP_DIR:-}" ]]; then
  export APP_BAMBUDDY_APP_DIR="$(dirname "${EXPORTS_APP_DIR}")/my3d-bambuddy"
fi

# Prefer Bambuddy's dependency export when present. For older installed
# Bambuddy packages without exports.sh, current Umbrel still passes a JSON map
# of the physical data roots for the app and all dependencies. This preserves
# relocated storage even when the provider package predates our export contract.
if [[ -z "${APP_BAMBUDDY_DATA_DIR:-}" ]]; then
  _bambuddy_data_root=""
  if [[ -n "${SCRIPT_APP_DATA_ROOTS:-}" ]] && command -v jq >/dev/null 2>&1; then
    _bambuddy_data_root="$(
      printf '%s' "${SCRIPT_APP_DATA_ROOTS}" \
        | jq --exit-status --raw-output --arg app "my3d-bambuddy" '.[$app] // empty' 2>/dev/null \
        || true
    )"
  fi

  if [[ "${_bambuddy_data_root}" = /* ]]; then
    export APP_BAMBUDDY_DATA_DIR="${_bambuddy_data_root}"
  else
    export APP_BAMBUDDY_DATA_DIR="${APP_BAMBUDDY_APP_DIR}/data"
  fi
  unset _bambuddy_data_root
fi
