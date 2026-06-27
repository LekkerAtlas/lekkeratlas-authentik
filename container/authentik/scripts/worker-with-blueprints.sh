#!/usr/bin/env bash
set -Eeuo pipefail

source /usr/local/lib/lekkeratlas/common.sh

worker_pid=""

state_dir="${LEKKERATLAS_STATE_DIR:-/tmp/lekkeratlas}"
blueprint_ready_marker="${state_dir}/blueprints-ready"

prepare_state_dir() {
  mkdir -p "$state_dir"
  rm -f "$blueprint_ready_marker"
}

shutdown() {
  log "Received shutdown signal."

  if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
    kill "$worker_pid" 2>/dev/null || true

    set +e
    wait "$worker_pid" 2>/dev/null
    set -e
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

apply_blueprints_with_retries() {
  local max_attempts="${AUTHENTIK_BLUEPRINT_APPLY_ATTEMPTS:-5}"
  local sleep_seconds="${AUTHENTIK_BLUEPRINT_APPLY_SLEEP_SECONDS:-5}"

  for attempt in $(seq 1 "$max_attempts"); do
    log "Blueprint deployment attempt ${attempt}/${max_attempts}"

    if /usr/local/lib/lekkeratlas/apply-blueprints-by-filename.sh; then
      log "Blueprint deployment succeeded."
      return 0
    fi

    if [[ "$attempt" -lt "$max_attempts" ]]; then
      log "Blueprint deployment failed. Waiting ${sleep_seconds}s before retrying..."
      sleep "$sleep_seconds"
    fi
  done

  log "Blueprint deployment failed after ${max_attempts} attempt(s)."
  return 1
}

stop_worker_and_exit() {
  local exit_code="$1"

  if [[ -n "$worker_pid" ]] && kill -0 "$worker_pid" 2>/dev/null; then
    log "Stopping Authentik worker."
    kill "$worker_pid" 2>/dev/null || true

    set +e
    wait "$worker_pid" 2>/dev/null
    set -e
  fi

  exit "$exit_code"
}

trap shutdown TERM INT

prepare_state_dir

log "Starting Authentik worker..."
ak worker &
worker_pid="$!"

if is_true "${AUTHENTIK_BLUEPRINT_APPLY_ENABLED:-true}"; then
  if ! wait_for_authentik_ready; then
    log "Stopping because Authentik did not become ready."
    stop_worker_and_exit 1
  fi

  log "Applying LekkerAtlas blueprints."

  if ! apply_blueprints_with_retries; then
    log "Stopping because blueprint deployment failed."
    stop_worker_and_exit 1
  fi

  log "Blueprint deployment completed successfully."
  date -Iseconds >"$blueprint_ready_marker"
else
  log "Blueprint applier is disabled."
fi

set +e
wait "$worker_pid"
worker_status="$?"
set -e

log "Authentik worker exited with status ${worker_status}."
exit "$worker_status"
