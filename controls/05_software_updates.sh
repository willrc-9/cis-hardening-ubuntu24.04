#!/usr/bin/env bash

manage_software_updates() {

	local weak_deps_conf="/etc/apt/apt.conf.d/60-cis-weak-deps.conf"
	local failed=0


	# Audit Mode -------------------------------------------------------------------------
	if [[ "$MODE" == "audit" ]]; then
		
		# 1.2.1.1 - signed by (manual check required)
		log_info "Audit (1.2.1.1): The 'Signed-By' option in sources.list requires manual validation."

		#1.2.1.2: Weak dependencies
		if ! grep -q 'APT::Install-Recommends "false";' "$weak_deps_conf" 2>/dev/null || \
		   ! grep -q 'APT::Install-Suggests "false";' "$weak_deps_conf" 2>/dev/null; then
		    log_warn "Audit Failed (1.2.1.2): Weak dependencies are not disabled."
		    failed=1
		fi

		# Helper function for auditing permissions
		check_perms() {
			local path="$1"
			local max_perm="$2"

			if [[ -e "$path" ]]; then
				local current_perm current_owner
				current_perm=$(stat -c "%a" "$path")
				current_owner=$(stat -c "%U:%G" "$path")

				# Check if permissions exceed max allowed or owner is not root:root
				if [[ "$current_perm" > "$max_perm" ]] || [[ "$current_owner" != "root:root" ]]; then
					log_warn "Audit Failed: $path has permissions $current_perm $current_owner (Requires max $max_perm root:root)"
					failed=1
				fi
			fi
		}

		# 1.2.1.4, 1.2.1.5, 1.2.1.7, 1.2.1.8 - Directory permissions
		for dir in /etc/apt/trusted.gpg.d /etc/apt/auth.conf.d /usr/share/keyrings /etc/apt/sources.list/d; do
			check_perms "$dir" "755"
		done

		#1.2.1.3, 1.2.1.6, 1.2.1.9: File permissions (644 for most, 640 for auth files)
		#using find to grab all files in the directories and pass them to check_perms

		while IFS= read -r file; do check_perms "$file" "644"; done < <(find /etc/apt/trusted.gpg.d -type f 2>/dev/null)
		while IFS= read -r file; do check_perms "$file" "644"; done < <(find /usr/share/keyrings -type f 2>/dev/null)
		while IFS= read -r file; do check_perms "$file" "644"; done < <(find /etc/apt/sources.list.d -type f 2>/dev/null)
        	while IFS= read -r file; do check_perms "$file" "640"; done < <(find /etc/apt/auth.conf.d -type f 2>/dev/null)

		#1.2.2.1 Package updates
        	apt-get update -qq
        	local installable_updates
        	installable_updates=$(apt-get -s upgrade | grep -c "^Inst" || true)
        
        	if [[ "$installable_updates" -gt 0 ]]; then
            		log_warn "Audit Failed (1.2.2.1): System has $installable_updates pending updates available for immediate installation."
            		failed=1
        	fi

		if [[ $failed -eq 0 ]]; then
			log_success "Audit Passed: Package management (CIS 1.2.1.x - 1.2.2.x) is secured."
		fi
		return $failed
	fi

	# Apply mode ------------------------------------------------------------------
    log_info "Applying control: Software Updates"
    if ask_yes_no "Disable APT weak dependencies?"; then
        echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/60-disable-recommends
        echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/60-disable-recommends
        log_success "Disabled APT weak dependencies."
    fi

    if ask_yes_no "Apply APT directory permissions?"; then
        chown -R root:root /etc/apt
        find /etc/apt -type d -exec chmod 755 {} \;
        log_success "Applied directory permissions to /etc/apt."
    fi

    if ask_yes_no "Apply permissions to package manager files?"; then
        find /etc/apt -type f -exec chmod 644 {} \;
        log_success "Applied file permissions to /etc/apt files."
    fi
}

run_software_updates() {
    	log_info "Starting CIS Section 1.2: Software Updates"
    	manage_software_updates
    	log_success "Software updates section completed."
}

register_control "software_updates" "run_software_updates"
