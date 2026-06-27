#!/usr/bin/env bash
set -Eeuo pipefail

state_dir="${LEKKERATLAS_STATE_DIR:-/tmp/lekkeratlas}"
ready_marker="${state_dir}/blueprints-ready"
failed_marker="${state_dir}/blueprints-failed"

if [[ "${LEKKERATLAS_HEALTH_REQUIRE_BLUEPRINTS:-false}" == "true" ]]; then
  if [[ -f "$failed_marker" ]]; then
    echo "Blueprint deployment failed:" >&2
    cat "$failed_marker" >&2
    exit 1
  fi

  if [[ ! -f "$ready_marker" ]]; then
    echo "Blueprint deployment has not completed yet." >&2
    exit 1
  fi
fi

ak healthcheck >/dev/null 2>&1
