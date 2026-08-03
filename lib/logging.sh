#!/usr/bin/env bash

LOG_FILE="${LOG_FILE:-/var/log/cis-hardening.log}"

init_logging() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
}

log() {
  local level="$1"
  shift

  printf "[%s] [%s] %s\n" \
    "$level" \
    "$*" | tee -a "$LOG_FILE"
}

log_info() {
  log "INFO" "$@"
}

log_warn() {
  log "WARN" "$@"
}

log_error() {
  log "ERROR" "$@"
}

log_success() {
  log "PASS" "$@"
}
