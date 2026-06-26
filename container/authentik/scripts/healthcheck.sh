#!/usr/bin/env bash
set -Eeuo pipefail

state_dir="/tmp/lekkeratlas"
blueprint_ready_marker="${state_dir}/blueprints-ready"
blueprint_failed_marker="${state_dir}/blueprints-failed"

ak healthcheck >/dev/null 2>&1

if [[ "${LEKKERATLAS_HEALTH_REQUIRE_BLUEPRINTS:-false}" == "true" ]]; then
  if [[ -f "$blueprint_failed_marker" ]]; then
    echo "Blueprint deployment failed:" >&2
    cat "$blueprint_failed_marker" >&2
    exit 1
  fi

  if [[ ! -f "$blueprint_ready_marker" ]]; then
    echo "Blueprint deployment has not completed yet." >&2
    exit 1
  fi
fi
