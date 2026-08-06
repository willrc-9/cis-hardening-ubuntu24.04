#!/usr/bin/env bash

manage_privilege_escalation() {
    local failed=0
    local sudoers_drop_in="/etc/sudoers.d/60-cis-hardening"
    local is_sudo_rs=0

    # Detect if the system is utilizing the new Rust-based sudo-rs
    if sudo -V 2>/dev/null | grep -qi "sudo-rs"; then
        is_sudo_rs=1
    fi

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 5.2.1 Ensure sudo is installed
        if ! dpkg-query -s sudo >/dev/null 2>&1; then
            log_warn "Audit Failed (5.2.1): 'sudo' package is not installed."
            failed=1
        fi

        # 5.2.2 Ensure sudo commands use pty
        if ! grep -Eiq '^\s*Defaults\s+([^#]+,\s*)?use_pty(,\s+\S+\s*)*(\s+#.*)?$' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
            log_warn "Audit Failed (5.2.2): sudo is not configured to use_pty."
            failed=1
        fi

        # 5.2.3 Ensure sudo log file exists
        if [[ $is_sudo_rs -eq 1 ]]; then
            log_info "Audit (5.2.3): Skipping 'logfile' check because sudo-rs natively uses syslog and rejects custom logfile parameters."
        else
            if ! grep -Eiq '^\s*Defaults\s+([^#]+,\s*)?logfile\s*=\s*("[^"]+"|\S+)(,\s+\S+\s*)*(\s+#.*)?$' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
                log_warn "Audit Failed (5.2.3): sudo custom logfile is not configured."
                failed=1
            fi
        fi

        # 5.2.4 Ensure users must provide password for escalation
        if grep -Eiq '^\s*[^#].*\!authenticate' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
            log_warn "Audit Failed (5.2.4): '!authenticate' is present in sudoers configuration."
            failed=1
        fi

        # 5.2.5 Ensure re-authentication for privilege escalation is not disabled globally
        if grep -Eiq '^\s*[^#].*(\!rootpw|\!targetpw|\!runaspw)' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
            log_warn "Audit Failed (5.2.5): Global disablement of re-authentication is present in sudoers configuration."
            failed=1
        fi

        # 5.2.6 Ensure sudo timestamp_timeout is configured (Added || true to prevent set -e crashes)
        local timeout_val
        timeout_val=$(grep -Eio '^\s*Defaults\s+([^#]+,\s*)?timestamp_timeout\s*=\s*[0-9]+' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' ' | tail -n 1 || true)
        
        if [[ -z "$timeout_val" ]] || [[ "$timeout_val" -gt 15 ]]; then
            log_warn "Audit Failed (5.2.6): sudo timestamp_timeout is not configured or is greater than 15."
            failed=1
        fi

        # 5.2.7 Ensure access to the su command is restricted
        if ! grep -Eiq '^\s*auth\s+required\s+pam_wheel\.so' /etc/pam.d/su 2>/dev/null; then
            log_warn "Audit Failed (5.2.7): Access to 'su' is not restricted via pam_wheel.so in /etc/pam.d/su."
            failed=1
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: Privilege escalation (sudo/su) is securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Privilege Escalation (CIS 5.2.x)"

    # 5.2.1 Ensure sudo is installed
    if ! dpkg-query -s sudo >/dev/null 2>&1; then
        if ask_yes_no "Install 'sudo' package? (5.2.1)"; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y sudo >/dev/null 2>&1
            log_success "Installed sudo."
        fi
    fi

    # 5.2.2, 5.2.3, 5.2.6 Configure strict sudoers defaults
    if ask_yes_no "Configure sudo defaults (use_pty, custom logfile, timestamp_timeout=15)? (5.2.2, 5.2.3, 5.2.6)"; then
        mkdir -p /etc/sudoers.d
        
        local temp_sudoers
        temp_sudoers=$(mktemp)
        
        # Pull existing cis-hardening configs to rebuild the file cleanly
        if [[ -f "$sudoers_drop_in" ]]; then
            grep -Ev '(use_pty|logfile|timestamp_timeout)' "$sudoers_drop_in" > "$temp_sudoers" 2>/dev/null || true
        fi

        echo "Defaults use_pty" >> "$temp_sudoers"
        
        if [[ $is_sudo_rs -eq 1 ]]; then
            log_info "Detected sudo-rs. Omitting the 'logfile' parameter to avoid syntax errors."
        else
            echo "Defaults logfile=\"/var/log/sudo.log\"" >> "$temp_sudoers"
        fi
        
        echo "Defaults timestamp_timeout=15" >> "$temp_sudoers"
        
        # Safely validate syntax before applying
        if visudo -cf "$temp_sudoers" >/dev/null 2>&1; then
            cat "$temp_sudoers" > "$sudoers_drop_in"
            chmod 0440 "$sudoers_drop_in"
            log_success "Safely validated and configured sudo defaults in $sudoers_drop_in."
        else
            log_warn "Syntax error detected! Aborting sudoers changes to prevent lockout."
        fi
        rm -f "$temp_sudoers"
    fi

    # 5.2.4 & 5.2.5 Manual review notice for NOPASSWD / !authenticate
    log_info "Note for 5.2.4 and 5.2.5: Searching for unsafe directives (!authenticate, !rootpw, etc.)..."
    local unsafe_sudoers
    unsafe_sudoers=$(grep -Eil '^\s*[^#].*(\!authenticate|\!rootpw|\!targetpw|\!runaspw)' /etc/sudoers /etc/sudoers.d/* 2>/dev/null || true)
    
    if [[ -n "$unsafe_sudoers" ]]; then
        log_warn "Unsafe authentication directives found in the following files:"
        echo "$unsafe_sudoers"
        log_warn "Please manually review these files and remove the offending directives to comply with 5.2.4 and 5.2.5."
    else
        log_success "No unsafe authentication directives found in sudoers configuration."
    fi

    # 5.2.7 Ensure access to the su command is restricted
    if ask_yes_no "Restrict 'su' command to the 'sudo' group via PAM wheel? (5.2.7)"; then
        if grep -q "pam_wheel.so" /etc/pam.d/su 2>/dev/null; then
            # Uncomment if it exists but is commented out
            sed -i 's/^#.*auth\s*required\s*pam_wheel.so.*/auth required pam_wheel.so use_uid group=sudo/' /etc/pam.d/su || true
        else
            # Add it below the first auth line
            sed -i '/^auth.*sufficient.*pam_rootok.so/a auth required pam_wheel.so use_uid group=sudo' /etc/pam.d/su || true
        fi
        log_success "Restricted 'su' access in /etc/pam.d/su."
    fi

    log_success "Privilege escalation configuration applied."
}

run_privilege_escalation() {
    log_info "Starting CIS Section 5.2: Configure Privilege Escalation"
    manage_privilege_escalation
}

register_control "privilege_escalation" "run_privilege_escalation"
