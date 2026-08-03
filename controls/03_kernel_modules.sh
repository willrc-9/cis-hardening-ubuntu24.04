#!/usr/bin/env bash

run_kernel_modules() {
  log_info "Starting CIS Kernel Module Hardening (USB/Firewire)"

  local misc_modules=(
    "usb-storage"
    "firewire-core"
  )
  for mod in "${misc_modules[@]}"; do
    if is_whitelisted "$mod"; then
      log_info "Skipping "$mod": Module is present in MODULE_ALLOWLIST."
      continue
    fi

    manage_kernel_module "$mod"
  done

  log_success "Kerner module hardening completed."

}

register_control "kernel_modules" "run_kernel_modules"
