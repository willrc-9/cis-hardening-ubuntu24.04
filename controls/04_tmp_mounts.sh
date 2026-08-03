#!/usr/bin/env bash

manage_tmp_mount() {
  local systemd_mount_file="/etc/systemd/system/tmp.mount"

  # Audit mode

  if [[ "$MODE" == "audit" ]]; then
    local failed=0

    if ! findmnt -n -M /tmp >/dev/null 2>&1; then
      log_warn "Audit Failed (1.1.2.1): /tmp is not a seperate mountpoint."
      failed=1
    else
      local current_opts
      current_opts="$(findmnt -n -M /tmp -o OPTIONS)"

      for opt in nodev nosuid noexec; do
	if ! echo "$current_opts" | grep -qw "$opt"; then
        	log_warn "Audit Failed (1.1.2.x): /tmp is missing the '$opt' mount option."
		failed=1
        fi
      done
    fi

    if [[ $failed -eq 0 ]]; then
      log_success "Audit Passed: /tmp is properly mounted with nodev, nosuid, and noexec."
    fi
    return $failed
  fi

  # -------- Apply mode

    log_info "Applying control: /tmp Mountpoint"
    if ask_yes_no "Create /tmp mountpoint (systemd tmp.mount)?"; then
        cp /usr/share/systemd/tmp.mount /etc/systemd/system/ 2>/dev/null || true
        sed -i 's/Options=.*/Options=mode=1777,strictatime,noexec,nodev,nosuid/' /etc/systemd/system/tmp.mount
        log_success "/tmp mountpoint configured"
    fi
    
    if ask_yes_no "Unmask tmp.mount?"; then
        systemctl unmask tmp.mount >/dev/null 2>&1 || true
        log_success "Unmasked tmp.mount"
    fi

    if ask_yes_no "Reload systemd daemons and enable tmp.mount?"; then
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable --now tmp.mount >/dev/null 2>&1
        log_success "Systemd daemons reloaded and tmp.mount enabled"
    fi
}

run_tmp_mounts() {
	log_info "Starting CIS Section 1.1.2: /tmp Partition Hardening"

	manage_tmp_mount

	log_success "/tmp partition hardening completed."
}

register_control "tmp_mounts" "run_tmp_mounts"
