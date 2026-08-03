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

  # Apply mode

  log_info "Applying control: Securing /tmp mount (CIS 1.1.2.x)"

  #backup systemd unit file if already exists
  if [[ -f "$systemd_mount_file" ]]; then
	backup_file "$systemd_mount_file"
  fi

  #create systemd mount unit for /tmp with CIS compliant options
  cat > "$systemd_mount_file" <<EOF
[Unit]
Description=Temporary Directory (/tmp)
Documentation=man:hier(7)
Documentation=https://www.freedesktop.org/wiki/Software/systemd/APIFileSystems
ConditionPathIsSymbolicLink=!/tmp
DefaultDependencies=no
Conflicts=umount.target
Before=local-fs.target umount.target
After=swap.target

[Mount]
What=tmpfs
Where=/tmp
Type=tmpfs
Options=mode=1777,strictatime,noexec,nodev,nosuid

[Install]
WantedBy=local-fs.target
EOF


	#reload systemd to recognize new updates
	systemctl daemon-reload

	#ensure mount is unmasked and enabled to persist across reboots
	systemctl unmask tmp.mount
	systemctl enable tmp.mount

	#attempt to apply dynamically without requiring reboot
	if mountpoint -q /tmp; then
		mount -o remount,nodev,nosuid,noexec /tmp || log_warn "Could not remount /tmp dynamically. A system reboot may be required."
	else
		systemctl start tmp.mount || log_warn "Could not start tmp.mount dynamically. A system reboot may be required."
	fi

	log_success "Applied: /tmp mount configuration enforced."
	
}

run_tmp_mounts() {
	log_info "Starting CIS Section 1.1.2: /tmp Partition Hardening"

	manage_tmp_mount

	log_success "/tmp partition hardening completed."
}

register_control "tmp_mounts" "run_tmp_mounts"
