#!/usr/bin/env bash
manage_bootloader() {
    local failed=0
    local grubcfg="/boot/grub/grub.cfg"
    local output=""
    local expected=""
    
# --- AUDIT MODE ---
	if [[ "$MODE" == "audit" ]]; then
		
		# Check if the superuser is set correctly
		if grep -q "^set superusers=\"$USER\"" "$grubcfg"; then
			
			# Check if the pbkdf2 format exists for the user
			if grep -q "^password_pbkdf2 $USER grub\.pbkdf2\.sha512" "$grubcfg"; then
				log_success "Audit Passed 1.4.1"
			else
				failed=1
				log_warn "Audit Failed 1.4.1: Password hash missing or incorrect."
			fi
			
		else
			failed=1
			log_warn "Audit Failed 1.4.1: Superusers not configured correctly."
		fi
		
		return $failed
	fi

    # --- APPLY MODE ---
    if ask_yes_no "Create Bootloader PW?"; then
        read -s -p "Enter new GRUB PW: " grub_pass
        echo ""
        read -s -p "Reenter GRUB PW: " grub_pass2
        echo ""

        if [[ "$grub_pass" == "$grub_pass2" ]]; then
            raw_output=$(echo -e "$grub_pass\n$grub_pass" | grub-mkpasswd-pbkdf2 --iteration-count=600000 --salt=64)
	    # This tells awk to ONLY execute the print command if the line contains the word 'PBKDF2'
	    grub_hash=$(echo "$raw_output" | awk '/PBKDF2/ {print $NF}')
            log_success "GRUB hash successfully generated and captured."

            # Note: Changed the first '>>' to '>' so it overwrites instead of stacking 
            # if run multiple times.
            echo "#!/bin/sh" > /etc/grub.d/01_users
            echo "cat <<EOF" >> /etc/grub.d/01_users
            # Fixed: Escaped the inner quotes
            echo "set superusers=\"$USER\"" >> /etc/grub.d/01_users
            echo "password_pbkdf2 $USER $grub_hash" >> /etc/grub.d/01_users
            echo "EOF" >> /etc/grub.d/01_users
            
            # Fixed: Added the commands to actually apply the changes!
            chmod +x /etc/grub.d/01_users
            update-grub
            
            log_success "Created /etc/grub.d/01_users and updated bootloader."
        else
            log_warn "Passwords do not match. Aborting."
            failed=1
        fi
    fi
}

run_bootloader2() {
    log_info "Starting bootloader configuration..."
    manage_bootloader
    log_success "Completed bootloader section: CIS 1.4.X"
}

register_control "bootloader2" "run_bootloader2"
