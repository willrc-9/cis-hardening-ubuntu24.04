#!/usr/bin/env bash

manage_kernel_module() {
  local module="$1"
  local conf_file="/etc/modprobe.d/cis_${module}.conf"

  if [[ "$MODE" == "audit" ]]; then
    local failed=0
    if is_module_loaded "$module"; then
      log_warn "Audit Failed: Kernel module '$module' is currently loaded."
      failed=1
    fi
    if [[ ! -f "$conf_file" ]] || ! grep -q "blacklist $module" "$conf_file"; then
      log_warn "Audit Failed: Blacklist configuration for '$module' is missing or incomplete."
      failed=1
    fi
    if [[ $failed -eq 0 ]]; then
      log_success "Audit Passed: Kernel module '$module' is correctly disabled."
    fi
    return $failed
  fi

  log_info "Applying control: Disabling kernel module '$module'"

  backup_file "$conf_file"

  cat >"$conf_file" <<EOF
install $module /bin/false
blacklist $module
EOF

  if is_module_loaded "$module"; then
    modprobe -r "$module" || log_warn "Could not remove in-use module: '$module'. A system reboot may be required."
  fi

  log_success "Applied: Kernel module '$module' configuration enforced."
}

run_filesystem() {
  log_info "Starting CIS Section 1.1.1: Filesystem Hardening"

  # CIS 1.1.1.1 through 1.1.1.8
  local fs_modules=(
    "cramfs"
    "freevxfs"
    "hfs"
    "hfsplus"
    "jffs2"
    "overlay"
    "squashfs"
    "udf"
  )

  for mod in "${fs_modules[@]}"; do
    if is_whitelisted "$mod"; then
      log_info "Skipping '$mod': Module is present in MODULE_ALLOWLIST."
      continue
    fi

    manage_kernel_module "$mod"
  done

  log_success "Filesystem hardening section completed."
}

register_control "filesystem" "run_filesystem"
