#!/usr/bin/env bash

manage_banners() {
	local failed=0
	local banner_text=" *** WARNING QUEEN ANNE'S COUNTY (QAC) IT SYSTEM ***
 You are accessing a system owned and operated by Queen Anne's County.
 Use of this system is restricted to authorized users only and by continuing to use this system,
 you agree to do so in accordance with the IT Acceptable Use Policy (700-001).
 Systems and networks are monitored for security purposes.
 Unauthorized use is strictly prohibited and may result in disciplinary action, civil liability, and/or criminal prosecution.
 If you are not authorized to access this system, disconnect immediately.
 For support, or to report missing equipment, please call 410-758-6607."

	local files=(
		"/etc/motd"
		"/etc/issue"
		"/etc/issue.net"
	)

	# audit mode
	if [[ "$MODE" == "audit" ]]; then

		# 1.6.1-1.6.3
		for file in "/etc/issue" "/etc/issue.net"; do
			if [[ -f "$file" ]]; then
				if grep -Eiq '(\\v|\\r|\\m|\\s|Ubuntu)' "$file"; then
					log_warn "Audit Failed (1.6.x): $file contains OS or kernel information."
					failed=1
				fi
			else
				log_warn "Audit Failed (1.6.x): $file does not exist."
				failed=1
			fi
		done

		#1.6.5 ensure sshd warning banner is configured
		if [[ -f /etc/ssh/sshd_config ]]; then
			if ! grep -q "^Banner /etc/issue.net" /etc/ssh/sshd_config; then
				log_warn "Audit Failed (1.6.5): SSH Banner is not configured to use /etc/issue.net."
				failed=1
			fi
		fi

		#1.6.6-1.6.10
		for file in "${files[@]}"; do
			if [[ -e "$file" ]]; then
				local current_perm current_owner
				current_perm=$(stat -c "%a" "$file")
				current_owner=$(stat -c "%U:%G" "$file")
				
				if [[ "$current_perm" > "644" ]]; then
					log_warn "Audit Failed (1.6.x): $file permissions are $current_perm (Requires max 644)."
					failed=1
				fi
			fi
		done

		if [[ $failed -eq 0 ]]; then
			log_success "Audit Passed: Command line warning banners are fully secured."
		fi
		return $failed
	fi

	# apply mode
	log_info "Applying control: Command Line Warning Banners (CIS 1.6.x)"
	log_info "To change the warning banner, please edit the banner_text variable in 09_banners.sh"

	#1.6.1-1.6.3 write legal banner and remove os info
	for file in "${files[@]}"; do
		#create file if it doesnt exist, or overwrite it with the safe banner
		echo "$banner_text" > "$file"
	done
	log_success "Applied (1.6.1 - 1.6.3): Injected standard legal banners."

	#1.6.4 disable MOTD scripts (pam_motd)
	#Ubuntu dynamically updates the MOTD with system info. removing exec permissions stops this
	if [[ -d "/etc/update-motd.d" ]]; then
		chmod -R -x /etc/update-motd.d/ 2>/dev/null || true
		log_success "Applied (1.6.4): Disabled dynamic pam_motd scripts."
	fi

	#1.6.5 configure ssh banner
	if [[ -f /etc/ssh/sshd_config ]]; then
		backup_file "/etc/ssh/sshd_config"

		#remove existing banner directives to prevent duplicates
		sed -i '/^Banner /d' /etc/ssh/sshd_config
		sed -i '/^#Banner /d' /etc/ssh/sshd_config

		#append the correct banner directive
		echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config

		#restart ssh to apply changes if running
		if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
			systemctl restart ssh >/dev/null 2>&1 || true
		fi
		log_success "Applied (1.6.5): Configured SSH daemon to use /etc/issue.net."
	else
		log_warn "SSH daemon is not installed. Skipping SSH banner configuration."
	fi

	#1.6.6-1.6.10 lock down permissions
	for file in "${files[@]}"; do
		if [[ -e "$file" ]]; then
			chown root:root "$file"
			chmod 644 "$file"
		fi
	done
	log_success "Applied (1.6.6 - 1.6.10): Enforced strict permissions on banner files."

	log_success "Command line warning banners configuration applied."
}

run_banners() {
	log_info "Starting CIS Section 1.6: Configure Command Line Warning Banners"
	manage_banners
}

register_control "banners" "run_banners"
