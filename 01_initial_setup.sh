#!/usr/bin/env bash

run_initial_setup() {
  log_info "Running initial setup phase..."
  require_root

  if ! is_ubuntu; then
    log_error "Unsupported OS. This hardening framework requires Ubuntu."
    exit 1
  fi

  require_commands apt systemctl grep sed awk find sysctl modprobe lsmod

  # Only create directories if we are actively applying changes
  if [[ "$MODE" == "apply" ]]; then
    ensure_directory /var/log
    ensure_directory "$BACKUP_DIR"
    log_success "Required framework directories verified/created."
  else
    log_info "Audit Mode: Directory creation skipped."
  fi

  log_info "Target OS: Ubuntu $(get_ubuntu_version)"
  log_info "Kernel: $(get_kernel)"
  log_info "Hostname: $(get_hostname)"
}

register_control "initial" "run_initial_setup"
