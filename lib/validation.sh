#!/usr/bin/env bash

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "Run this script as root."
    exit 1
  fi
}

require_command() {
  local cmd="$1"

  command -v "$cmd" >/dev/null 2>&1 || {
    log_error "Missing required command: $cmd"
    exit 1
  }
}

require_commands() {
  local cmd
  for cmd in "$@"; do
    require_command "$cmd"
  done
}

is_whitelisted() {
   local target="$1"
   local item

   # Check if MODULE_ALLOWLIST is defined and not empty
   if [[ "$(declare -p MODULE_ALLOWLIST 2>/dev/null)" =~ "declare -a" ]]; then
     for item in "${MODULE_ALLOWLIST[@]}"; do
       if [[ "$item" == "$target" ]]; then
        return 0
       fi
     done
   fi

   return 1
}
