#!/usr/bin/env bash

manage_ssh_server() {
    local failed=0
    local ssh_drop_in="/etc/ssh/sshd_config.d/60-cis-hardening.conf"

    # Define standard CIS SSH parameters (Controls 5.1.5 - 5.1.22)
    local ssh_params=(
        "Banner /etc/issue.net"
        "ClientAliveInterval 300"
        "ClientAliveCountMax 3"
        "X11Forwarding no"
        "AllowTcpForwarding no"
        "GSSAPIAuthentication no"
        "HostbasedAuthentication no"
        "IgnoreRhosts yes"
        "LoginGraceTime 60"
        "LogLevel VERBOSE"
        "MaxAuthTries 4"
        "MaxStartups 10:30:100"
        "MaxSessions 10"
        "PermitEmptyPasswords no"
        "PermitRootLogin no"
        "PermitUserEnvironment no"
        "UsePAM yes"
    )

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 5.1.1 Ensure access to /etc/ssh/sshd_config is configured
        if [[ -f /etc/ssh/sshd_config ]]; then
            local sshd_stat
            sshd_stat="$(stat -c "%a %U %G" /etc/ssh/sshd_config)"
            if [[ "$sshd_stat" != "600 root root" ]]; then
                log_warn "Audit Failed (5.1.1): /etc/ssh/sshd_config permissions or ownership are incorrect ($sshd_stat)."
                failed=1
            fi
        fi

        # 5.1.2 Ensure access to SSH private host key files is configured
        local priv_keys_failed=0
        for key in /etc/ssh/ssh_host_*_key; do
            if [[ -f "$key" ]]; then
                local key_stat
                key_stat="$(stat -c "%a %U %G" "$key")"
                if [[ "$key_stat" != "600 root root" && "$key_stat" != "640 root ssh_keys" ]]; then
                    priv_keys_failed=1
                fi
            fi
        done
        if [[ $priv_keys_failed -eq 1 ]]; then
            log_warn "Audit Failed (5.1.2): One or more SSH private keys have incorrect permissions or ownership."
            failed=1
        fi

        # 5.1.3 Ensure access to SSH public host key files is configured
        local pub_keys_failed=0
        for pub in /etc/ssh/ssh_host_*_key.pub; do
            if [[ -f "$pub" ]]; then
                local pub_stat
                pub_stat="$(stat -c "%a %U %G" "$pub")"
                if [[ "$pub_stat" != "644 root root" ]]; then
                    pub_keys_failed=1
                fi
            fi
        done
        if [[ $pub_keys_failed -eq 1 ]]; then
            log_warn "Audit Failed (5.1.3): One or more SSH public keys have incorrect permissions or ownership."
            failed=1
        fi

        # Audit SSH daemon parameters
        for param in "${ssh_params[@]}"; do
            local key="${param%% *}"
            local expected_val="${param#* }"
            local active_val
            
            # Use sshd -T to evaluate the live running configuration
            active_val=$(sshd -T 2>/dev/null | grep -i "^${key}\b" | awk '{print $2}')
            
            # Convert to lowercase for reliable comparison
            if [[ "${active_val,,}" != "${expected_val,,}" ]]; then
                log_warn "Audit Failed (5.1.x): SSH parameter '$key' is set to '$active_val' (Expected: '$expected_val')."
                failed=1
            fi
        done

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: SSH Server is securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Configure SSH Server (CIS 5.1.x)"

    # 5.1.1 - 5.1.3 Secure SSH file permissions
    if ask_yes_no "Restrict permissions on SSH configuration and host key files (5.1.1 - 5.1.3)?"; then
        if [[ -f /etc/ssh/sshd_config ]]; then
            chown root:root /etc/ssh/sshd_config
            chmod 600 /etc/ssh/sshd_config
        fi
        
        # Secure private keys (0600 root:root)
        find /etc/ssh -xdev -type f -name 'ssh_host_*_key' -exec chown root:root {} \;
        find /etc/ssh -xdev -type f -name 'ssh_host_*_key' -exec chmod 0600 {} \;
        
        # Secure public keys (0644 root:root)
        find /etc/ssh -xdev -type f -name 'ssh_host_*_key.pub' -exec chown root:root {} \;
        find /etc/ssh -xdev -type f -name 'ssh_host_*_key.pub' -exec chmod 0644 {} \;
        
        log_success "Secured SSH configuration and host key permissions."
    fi

    # 5.1.5 - 5.1.22 Apply Drop-in Configuration
    if ask_yes_no "Apply strict CIS SSH parameters (Timeouts, Root Login, Passwords, etc.)?"; then
        mkdir -p /etc/ssh/sshd_config.d/
        
        echo "# CIS Ubuntu 24.04 LTS Hardening - Section 5.1" > "$ssh_drop_in"
        for param in "${ssh_params[@]}"; do
            echo "$param" >> "$ssh_drop_in"
        done
        
        # 5.1.4 Explicitly handle Allowed/Denied Users. Leaving commented by default to avoid accidental lockouts.
        echo "" >> "$ssh_drop_in"
        echo "# 5.1.4 - Ensure sshd access is configured" >> "$ssh_drop_in"
        echo "# Uncomment and configure the following to restrict access to specific users/groups:" >> "$ssh_drop_in"
        echo "# AllowUsers <username>" >> "$ssh_drop_in"
        echo "# AllowGroups <groupname>" >> "$ssh_drop_in"
        
        log_success "Applied SSH parameters to $ssh_drop_in."
        
        # Test SSH configuration before restarting
        if sshd -t; then
            systemctl restart sshd >/dev/null 2>&1 || systemctl restart ssh >/dev/null 2>&1
            log_success "SSH configuration validated and service restarted."
        else
            log_warn "SSH configuration validation failed! Changes have NOT been restarted. Please review $ssh_drop_in."
        fi
    fi

    log_success "SSH server configuration applied."
}

run_ssh_server() {
    log_info "Starting CIS Section 5.1: Configure SSH Server"
    manage_ssh_server
}

register_control "ssh_server" "run_ssh_server"
