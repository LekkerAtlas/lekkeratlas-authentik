#!/usr/bin/env bash

log() {
  echo "[lekkeratlas] $*" >&2
}

is_true() {
  case "${1:-}" in
  true | True | TRUE | 1 | yes | YES | y | Y) return 0 ;;
  *) return 1 ;;
  esac
}
