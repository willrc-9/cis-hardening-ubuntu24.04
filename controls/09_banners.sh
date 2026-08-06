#!/usr/bin/env bash

manage_banners() {
	local failed=0
	local banner_text="Custom Message Here
	Give a legal warning
	Add a missing device callback number too"

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
	# --- APPLY MODE ---
    log_info "Applying control: Command Line Warning Banners"
    for file in "${files[@]}"; do
        if ask_yes_no "Add warning banner and configure permissions for $file?"; then
            echo "$banner_text" > "$file"
            chown root:root "$file"
            chmod 644 "$file"
            log_success "Injected banner and secured $file"
        fi
    done

    if ask_yes_no "Disable dynamic MOTD scripts (pam_motd)?"; then
        if [[ -d "/etc/update-motd.d" ]]; then chmod -R -x /etc/update-motd.d/ 2>/dev/null || true; fi
        rm -f /run/motd.dynamic 2>/dev/null || true
        for pam_file in "/etc/pam.d/login" "/etc/pam.d/sshd"; do
            if [[ -f "$pam_file" ]]; then backup_file "$pam_file"; sed -i '/pam_motd.so motd=\/run\/motd.dynamic/s/^/#/' "$pam_file"; fi
        done
        log_success "Disabled dynamic pam_motd scripts."
    fi

    if ask_yes_no "Configure SSH daemon warning banner?"; then
        if [[ -f /etc/ssh/sshd_config ]]; then
            backup_file "/etc/ssh/sshd_config"
            sed -i '/^Banner /d' /etc/ssh/sshd_config
            sed -i '/^#Banner /d' /etc/ssh/sshd_config
            echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
            if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
                systemctl restart sshd >/dev/null 2>&1 || true
            fi
            log_success "Configured SSH daemon banner."
        fi
    fi

	}

run_banners() {
	log_info "Starting CIS Section 1.6: Configure Command Line Warning Banners"
	manage_banners
}

register_control "banners" "run_banners"
