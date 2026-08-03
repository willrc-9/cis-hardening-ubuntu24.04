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
	log_info "Applying control: Securing package management (CIS 1.2.1.x - 1.2.2.x)"

	# 1.2.1.1 - signed by
	log_info "(1.2.1.1): Skipping automated 'Signed-By' enforcement to prevent breaking 3rd-party repos. Please configure manually."
	
	# 1.2.1.2 - weak deps
	echo 'APT::Install-Recommends "false";' > "$weak_deps_conf"
	echo 'APT::Install-Suggests "false";' >> "$weak_deps_conf"
	log_success "Applied (1.2.1.2): Disabled weak dependencies."

	# 1.2.1.4, 1.2.1.5, 1.2.1.7, 1.2.1.8: Apply Directory Permissions
	for dir in /etc/apt/trusted.gpg.d /etc/apt/auth.conf.d /usr/share/keyrings /etc/apt/sources.list.d; do
		if [[ -d "$dir" ]]; then
            		chown root:root "$dir"
            		chmod 755 "$dir"
        fi
done

	# 1.2.1.3, 1.2.1.6, 1.2.1.9: Apply File Permissions
	find /etc/apt/trusted.gpg.d -type f -exec chown root:root {} + -exec chmod 644 {} + 2>/dev/null || true
    	find /usr/share/keyrings -type f -exec chown root:root {} + -exec chmod 644 {} + 2>/dev/null || true
    	find /etc/apt/sources.list.d -type f -exec chown root:root {} + -exec chmod 644 {} + 2>/dev/null || true
    
    	# auth.conf.d holds credentials, so files must be 640
    	find /etc/apt/auth.conf.d -type f -exec chown root:root {} + -exec chmod 640 {} + 2>/dev/null || true

    	log_success "Applied (1.2.1.3 - 1.2.1.9): Enforced strict permissions on package manager directories and files."
	# 1.2.2.1: Package Updates
    	log_info "Applying pending package updates (this may take a moment)..."
   	DEBIAN_FRONTEND=noninteractive apt-get update -qq
    	DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || log_warn "Failed to apply package updates."
    
    	log_success "Applied: Package management configuration enforced."
}

run_software_updates() {
    	log_info "Starting CIS Section 1.2: Software Updates"
    	manage_software_updates
    	log_success "Software updates section completed."
}

register_control "software_updates" "run_software_updates"
