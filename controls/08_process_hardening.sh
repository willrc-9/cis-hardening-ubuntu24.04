#!/usr/bin/env bash

manage_process_hardening() {
	local failed=0
	local sysctl_conf="/etc/sysctl.d/60-process-hardening.conf"
	local coredump_conf="/etc/systemd/coredump.conf"

	# Define the CIS required sysctl parameters
	declare -A sysctls=(
		["fs.protected_hardlinks"]="1"
		["fs.protected_symlinks"]="1"
		["kernel.yama.ptrace_scope"]="1"
		["fs.suid_dumpable"]="0"
		["kernel.dmesg_restrict"]="1"
		["kernel.kptr_restrict"]="2"
		["kernel.randomize_va_space"]="2"
	)

	# --- AUDIT MODE ---
	if [[ "$MODE" == "audit" ]]; then
        
		# 1.5.1 - 1.5.5, 1.5.8 - 1.5.9: Audit sysctl parameters
		for key in "${!sysctls[@]}"; do
			local expected_val="${sysctls[$key]}"
			local current_val
			current_val=$(sysctl -n "$key" 2>/dev/null)
            
			if [[ "$current_val" != "$expected_val" ]]; then
				log_warn "Audit Failed (1.5.x): $key is set to '$current_val' (Requires '$expected_val')."
				failed=1
			fi
		done
	
		# 1.5.6: Ensure prelink is not installed
		if is_pkg_installed "prelink"; then
			log_warn "Audit Failed (1.5.6): 'prelink' is installed and should be removed."
			failed=1
		fi
	
		# 1.5.7: Ensure Automatic Error Reporting (apport) is not enabled
		if systemctl is-enabled apport.service >/dev/null 2>&1 || systemctl is-active apport.service >/dev/null 2>&1; then
			log_warn "Audit Failed (1.5.7): Automatic Error Reporting (apport) is active/enabled."
			failed=1
		fi
	
		# 1.5.10 & 1.5.11: Ensure systemd-coredump is configured
		if [[ -f "$coredump_conf" ]]; then
			if ! grep -q "^Storage=none" "$coredump_conf"; then
				log_warn "Audit Failed (1.5.11): Coredump Storage is not set to 'none'."
				failed=1
			fi
			if ! grep -q "^ProcessSizeMax=0" "$coredump_conf"; then
				log_warn "Audit Failed (1.5.10): Coredump ProcessSizeMax is not set to '0'."
				failed=1
			fi
		else
			log_warn "Audit Failed (1.5.10/11): $coredump_conf does not exist."
			failed=1
		fi
	
		if [[ $failed -eq 0 ]]; then
			log_success "Audit Passed: Additional Process Hardening is fully secured."
		fi
		return $failed
	fi


	# --- APPLY MODE ---
	log_info "Applying control: Process Hardening"
    
	if ask_yes_no "Apply strict kernel sysctl parameters (including kptr_restrict)?"; then
		# Safely recreate the sysctl file without prematurely destroying it
		echo "# CIS System Kernel Hardening" > "$sysctl_conf"
		for key in "${!sysctls[@]}"; do
			echo "$key = ${sysctls[$key]}" >> "$sysctl_conf"
			sysctl -w "$key=${sysctls[$key]}" >/dev/null 2>&1 || true
			log_success "Applied $key"
		done
		# Force the system to reload the drop-in file immediately
		sysctl -p "$sysctl_conf" >/dev/null 2>&1 || true
	fi

	if ask_yes_no "Remove 'prelink' package?"; then
		DEBIAN_FRONTEND=noninteractive apt-get purge -y prelink >/dev/null 2>&1 || true
		log_success "Removed prelink"
	fi

	if ask_yes_no "Disable Automatic Error Reporting (apport)?"; then
		systemctl stop apport.service >/dev/null 2>&1 || true
		systemctl disable apport.service >/dev/null 2>&1 || true
		systemctl mask apport.service >/dev/null 2>&1 || true
		log_success "Disabled apport"
	fi

	if ask_yes_no "Configure systemd-coredump?"; then
		if [[ ! -f "$coredump_conf" ]]; then touch "$coredump_conf"; chmod 644 "$coredump_conf"; chown root:root "$coredump_conf"; else backup_file "$coredump_conf"; fi
		if ! grep -q "^\[Coredump\]" "$coredump_conf"; then echo "[Coredump]" >> "$coredump_conf"; fi
		sed -i '/^Storage=/d' "$coredump_conf"
		sed -i '/^ProcessSizeMax=/d' "$coredump_conf"
		echo "Storage=none" >> "$coredump_conf"
		echo "ProcessSizeMax=0" >> "$coredump_conf"
		systemctl daemon-reload >/dev/null 2>&1 || true
		log_success "Configured systemd-coredump"
	fi
}

run_process_hardening() {
	log_info "Starting CIS Section 1.5: Additional Process Hardening"
	manage_process_hardening
}

register_control "process_hardening" "run_process_hardening"
