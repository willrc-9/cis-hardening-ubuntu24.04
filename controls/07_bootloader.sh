#!/usr/bin/env bash

manage_bootloader() {
	local failed=0
	local grub_cfg="/boot/grub/grub.cfg"
	local grub_dir="/etc/grub.d"

	# Audit Mode --------------------------------------------------------
	if [[ "$MODE" == "audit" ]]; then
		# 1.4.2 - Ensure access to bootloader config is configured
		if [[ -f "$grub_cfg" ]]; then
			local current_perm current_owner
			current_perm=$(stat -c "%a" "$grub_cfg")
			current_owner=$(stat -c "%U:%G" "$grub_cfg")

			# The generated grub.cfg should be strictly locked down (max 400 or 600)
			if [[ "$current_owner" != "root:root" ]]; then
				log_warn "Audit Failed (1.4.2): $grub_cfg owner is $current_owner (Requires root:root)."
				failed=1
			fi

			# Use string compare to ensure group/others have no access
			if [[ "$current_perm" > "600" ]]; then
				log_warn "Audit Failed (1.4.2): $grub_cfg permissions are $current_perm (Requires 400 or 600)."
				failed=1
			fi
		else
			log_warn "Audit Failed (1.4.2): GRUB configuration file not found at $grub_cfg."
			failed=1
		fi

		# 1.4.2 - Check /etc/grub.d/ directory permissions
		if [[ -d "$grub_dir" ]]; then
			while IFS= read -r file; do
				local file_owner file_perm
				file_owner=$(stat -c "%U:%G" "$file")
				file_perm=$(stat -c "%A" "$file")

				if [[ "$file_owner" != "root:root" ]]; then
					log_warn "Audit Failed (1.4.2): $file owner is $file_owner (Requires root:root)."
					failed=1
				fi

				# Ensure group and others do not have write access (the 'w' in the 5th and 8th positions)
				if [[ "${file_perm:5:1}" == "w" ]] || [[ "${file_perm:8:1}" == "w" ]]; then
					log_warn "Audit Failed (1.4.2): $file has excessive permissions $file_perm (Group/Others must not have write access)."
					failed=1
				fi
			done < <(find "$grub_dir" -type f 2>/dev/null)
		fi

		if [[ $failed -eq 0 ]]; then
			log_success "Audit Passed: Bootloader permissions are secured."
		fi
		return $failed
	fi
		
	# Apply Mode -------------------------------------------------------
	log_info "Applying control: Securing Bootloader Configurations (CIS 1.4.2)"

	# 1.4.2 - Ensure access to bootloader config is configured
	if [[ -f "$grub_cfg" ]]; then
		chown root:root "$grub_cfg"
		chmod 400 "$grub_cfg"
	fi

	# Lock down the grub template files used to generate the config
	if [[ -d "$grub_dir" ]]; then
		chown -R root:root "$grub_dir"
		chmod -R go-w "$grub_dir"
	fi

	log_success "Applied (1.4.2): Enforced strict permissions on GRUB configurations."
	
}

run_bootloader() {
	log_info "Starting CIS Section 1.4: Configure Bootloader"
	manage_bootloader
}

register_control "bootloader" "run_bootloader"
