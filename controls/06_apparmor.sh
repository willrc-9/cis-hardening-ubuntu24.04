#!/usr/bin/env bash

manage_apparmor() {
	local failed=0
	local sysctl_conf="/etc/sysctl.d/60-apparmor.conf"

	# Audit ------------------------------------------------
	
	if [[ "$MODE" == "audit" ]]; then

		# 1.3.1.1 - ensure apparmor pkg installed
		if ! is_pkg_installed "apparmor" || ! is_pkg_installed "apparmor-utils"; then
			log_warn "Audit Failed (1.3.1.1): AppArmor packages (apparmor, apparmor-utils) are not installed."
			failed=1
		fi
		
		#1.3.1.2 ensure apparmor is enabled in bootloader config
		if ! grep -q "apparmor=1" /etc/default/grub || ! grep -q "security=apparmor" /etc/default/grub; then
			log_warn "Audit Failed (1.3.1.2): AppArmor parameters are missing from GRUB configuration."
			failed=1
		fi

		#1.3.1.3 ensure all apparmor profiles are enforcing
		if command -v aa-status >/dev/null 2>&1; then
			local complain_count
			complain_count=$(aa-status 2>/dev/null | awk '/profiles are in complain mode/ {print $1}')

			if [[ -n "$complain_count" ]] && [[ "$complain_count" -gt 0 ]]; then
				log_warn "Audit Failed (1.3.1.3): There are $complain_count AppArmor profiles in complain mode."
				failed=1
			fi
		else
			log_warn "Audit Failed (1.3.1.3): AppArmor is not actively running (aa-status failed)."
			failed=1
		fi

		#1.3.1.4 ensure apparmor_restrict_unprivileged_unconfined is enabled
		local sysctl_val
		sysctl_val=$(sysctl -n kernel.apparmor_restrict_unprivileged_unconfined 2>/dev/null || echo "0")
		if [[ "$sysctl_val" != "1" ]]; then
			log_warn "Audit Failed (1.3.1.4): kernel.apparmor_restrict_unprivileged_unconfined is not enabled."
			failed=1
		fi

		if [[ $failed -eq 0 ]]; then
			log_success "Audit Passed: AppArmor is fully configured and enforcing."
		fi
		return $failed
	fi

	# Apply Mode ----------------------------------------------------------------------
	log_info "Applying control: Securing Mandatory Access Control (AppArmor) (CIS 1.3.1.x)"

	# 1.3.1.1 - install apparmor
	if !  is_pkg_installed "apparmor" || ! is_pkg_installed "apparmor-utils"; then
		log_info "Installing apparmor and apparmor-utils..."
		DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor apparmor-utils || log_warn "Failed to install AppArmor packages."
	fi

	#1.3.1.2 enable apparmor in grub
	if ! grep -q "apparmor=1" /etc/default/grub; then
		backup_file "/etc/default/grub"
		#safely append kernel parameters to GRUB_CMDLINE_LINUX
		sed -i 's/^\(GRUB_CMDLINE_LINUX=".*\)"/\1 apparmor=1 security=apparmor"/' /etc/default/grub
		update-grub >/dev/null 2>&1 || log_warn "Failed to update grub"
		log_info "Updated GRUB configuration. A system reboot is required for these boot parameters to take effect."
	fi

	systemctl enable apparmor >/dev/null 2>&1
	systemctl start apparmor >/dev/null 2>&1

	#1.3.1.3 enforce all profiles
	if command -v aa-enforce >/dev/null 2>&1; then
		log_info "Setting all AppArmor profiles to enforce mode..."

		aa-enforce /etc/apparmor.d/* >/dev/null 2>&1 || true
	fi

	log_success "Applied: AppArmor configuration enforced."

}

run_apparmor() {
	log_info "Starting CIS Section 1.3.1: Mandatory Access Control (AppArmor)"
	manage_apparmor
	log_success "AppArmor section completed."
}
register_control "apparmor" "run_apparmor"
