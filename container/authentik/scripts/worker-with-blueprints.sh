#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/lekkeratlas/common.sh

worker_pid=""
applier_pid=""
state_dir="${LEKKERATLAS_STATE_DIR:-/tmp/lekkeratlas}"
blueprint_ready_marker="${state_dir}/blueprints-ready"
blueprint_failed_marker="${state_dir}/blueprints-failed"

prepare_state_dir() {
  mkdir -p "$state_dir"
  rm -f "$blueprint_ready_marker" "$blueprint_failed_marker"
}

shutdown() {
  log "Received shutdown signal."

  if [[ -n "$applier_pid" ]] && kill -0 "$applier_pid" 2>/dev/null; then
    kill "$applier_pid" 2>/dev/null || true
    wait "$applier_pid" 2>/dev/null || true
  fi

  if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
    kill "$worker_pid" 2>/dev/null || true
    wait "$worker_pid" 2>/dev/null || true
  fi

  exit 143
}

wait_for_authentik_ready() {
  local max_attempts="${AUTHENTIK_READY_ATTEMPTS:-60}"
  local sleep_seconds="${AUTHENTIK_READY_SLEEP_SECONDS:-5}"

  log "Waiting for Authentik healthcheck..."

  for attempt in $(seq 1 "$max_attempts"); do
    if ak healthcheck >/dev/null 2>&1; then
      log "Authentik healthcheck is passing."
      return 0
    fi

    log "Authentik is not ready yet (${attempt}/${max_attempts}). Waiting ${sleep_seconds}s..."
    sleep "$sleep_seconds"
  done

  log "Timed out waiting for Authentik readiness."
  return 1
}

run_blueprint_applier() {
  local max_attempts="${AUTHENTIK_BLUEPRINT_APPLY_ATTEMPTS:-5}"
  local sleep_seconds="${AUTHENTIK_BLUEPRINT_APPLY_SLEEP_SECONDS:-3}"

  wait_for_authentik_ready || {
    echo "Authentik healthcheck did not become ready." >"$blueprint_failed_marker"
    return 1
  }

  for attempt in $(seq 1 "$max_attempts"); do
    log "Blueprint deployment attempt ${attempt}/${max_attempts}"

    if /usr/local/lib/lekkeratlas/apply-blueprints-by-filename.sh; then
      log "Blueprint deployment succeeded."
      date -Iseconds >"$blueprint_ready_marker"
      rm -f "$blueprint_failed_marker"
      return 0
    fi

    if [[ "$attempt" -lt "$max_attempts" ]]; then
      log "Blueprint deployment failed. Waiting ${sleep_seconds}s before retrying..."
      sleep "$sleep_seconds"
    fi
  done

  log "Blueprint deployment failed after ${max_attempts} attempts."
  echo "Blueprint deployment failed after ${max_attempts} attempts." >"$blueprint_failed_marker"
  return 1
}

trap shutdown TERM INT

prepare_state_dir

log "Starting Authentik worker..."
ak worker &
worker_pid="$!"

if is_true "${AUTHENTIK_BLUEPRINT_APPLY_ENABLED:-true}"; then
  (
    set +e
    run_blueprint_applier
  ) &
  applier_pid="$!"
else
  log "Blueprint applier is disabled."
fi

while true; do
  if ! kill -0 "$worker_pid" 2>/dev/null; then
    set +e
    wait "$worker_pid"
    worker_status="$?"
    set -e

    log "Authentik worker exited with status ${worker_status}."

    if [[ -n "$applier_pid" ]] && kill -0 "$applier_pid" 2>/dev/null; then
      kill "$applier_pid" 2>/dev/null || true
      wait "$applier_pid" 2>/dev/null || true
    fi

    exit "$worker_status"
  fi

  if [[ -n "$applier_pid" ]] && ! kill -0 "$applier_pid" 2>/dev/null; then
    set +e
    wait "$applier_pid"
    applier_status="$?"
    set -e

    applier_pid=""

    if [[ "$applier_status" != "0" ]]; then
      log "Blueprint deployment failed with status ${applier_status}."

      if is_true "${AUTHENTIK_BLUEPRINT_APPLY_REQUIRED:-true}"; then
        log "Stopping worker because AUTHENTIK_BLUEPRINT_APPLY_REQUIRED=true."
        kill "$worker_pid" 2>/dev/null || true
        wait "$worker_pid" 2>/dev/null || true
        exit "$applier_status"
      fi

      log "Continuing because AUTHENTIK_BLUEPRINT_APPLY_REQUIRED=false."
    else
      log "Blueprint deployment completed successfully."
    fi
  fi

  sleep 1
done
