#!/usr/bin/env bash

manage_pam() {
    local failed=0

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 5.3.1 Ensure PAM software packages are installed[cite: 1]
        if ! dpkg-query -s libpam-pwquality >/dev/null 2>&1; then
            log_warn "Audit Failed (5.3.1): 'libpam-pwquality' is not installed."
            failed=1
        fi

        # 5.3.2 Ensure PAM modules are enabled[cite: 1]
        local required_profiles=("unix" "faillock" "pwquality" "pwhistory")
        for profile in "${required_profiles[@]}"; do
            if ! grep -q "Name:" "/usr/share/pam-configs/$profile" 2>/dev/null; then
                log_warn "Audit Failed (5.3.2): PAM profile '$profile' is not active/available."
                failed=1
            fi
        done

        # 5.3.3.1 Configure pam_faillock (Lockout policy)[cite: 1]
        if ! grep -Eq '^\s*deny\s*=\s*[1-5]\b' /etc/security/faillock.conf 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.1): pam_faillock 'deny' is not set to 5 or less."
            failed=1
        fi
        if ! grep -Eq '^\s*unlock_time\s*=\s*([9-9][0-9]{2}|[1-9][0-9]{3,})\b' /etc/security/faillock.conf 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.1): pam_faillock 'unlock_time' is not configured to 900+ seconds."
            failed=1
        fi

        # 5.3.3.2 Configure pam_pwquality (Password complexity)[cite: 1]
        if ! grep -Eq '^\s*minlen\s*=\s*([1-9][4-9]|[2-9][0-9]+)\b' /etc/security/pwquality.conf 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.2): pam_pwquality 'minlen' is not 14 or greater."
            failed=1
        fi
        if ! grep -Eq '^\s*minclass\s*=\s*[4-9]\b' /etc/security/pwquality.conf 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.2): pam_pwquality 'minclass' is not 4 or greater."
            failed=1
        fi

        # 5.3.3.3 Configure pam_pwhistory (Password history)[cite: 1]
        if ! grep -Eq '^\s*remember\s*=\s*([5-9]|[1-9][0-9]+)\b' /etc/security/pwhistory.conf 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.3): pam_pwhistory 'remember' is not 5 or greater."
            failed=1
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: PAM is securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Pluggable Authentication Modules (CIS 5.3.x)"

    # 5.3.1 Install libpam-pwquality[cite: 1]
    if ! dpkg-query -s libpam-pwquality >/dev/null 2>&1; then
        if ask_yes_no "Install 'libpam-pwquality' to enforce password complexity? (5.3.1)"; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y libpam-pwquality >/dev/null 2>&1
            log_success "Installed libpam-pwquality."
        fi
    fi

    # 5.3.2 Enable PAM profiles[cite: 1]
    if ask_yes_no "Enable PAM profiles for faillock, pwquality, and pwhistory? (5.3.2)"; then
        
        # Create faillock profile per CIS benchmark specifications
        cat << 'EOF' > /usr/share/pam-configs/faillock
Name: Enforce failed login lockout
Default: yes
Priority: 0
Auth-Type: Primary
Auth:
	[default=die] pam_faillock.so authfail
	sufficient pam_faillock.so authsucc
Auth-Initial:
	required pam_faillock.so preauth
Account-Type: Primary
Account:
	required pam_faillock.so
EOF

        # Create pwhistory profile per CIS benchmark specifications
        cat << 'EOF' > /usr/share/pam-configs/pwhistory
Name: Enforce password history
Default: yes
Priority: 1024
Password-Type: Primary
Password:
	requisite pam_pwhistory.so
EOF

        # Enable the profiles system-wide
        pam-auth-update --enable faillock pwquality pwhistory >/dev/null 2>&1
        log_success "Created and enabled required PAM authentication profiles."
    fi

    # 5.3.3.1 Configure pam_faillock[cite: 1]
    if ask_yes_no "Configure account lockout (deny=5, unlock_time=900, even_deny_root)? (5.3.3.1)"; then
        local fl_conf="/etc/security/faillock.conf"
        sed -i -E 's/^\s*#?\s*deny\s*=.*/deny = 5/' "$fl_conf"
        sed -i -E 's/^\s*#?\s*unlock_time\s*=.*/unlock_time = 900/' "$fl_conf"
        sed -i -E 's/^\s*#?\s*even_deny_root.*/even_deny_root/' "$fl_conf"
        sed -i -E 's/^\s*#?\s*root_unlock_time\s*=.*/root_unlock_time = 60/' "$fl_conf"
        
        # Add if they don't exist
        grep -q "^deny" "$fl_conf" || echo "deny = 5" >> "$fl_conf"
        grep -q "^unlock_time" "$fl_conf" || echo "unlock_time = 900" >> "$fl_conf"
        grep -q "^even_deny_root" "$fl_conf" || echo "even_deny_root" >> "$fl_conf"
        grep -q "^root_unlock_time" "$fl_conf" || echo "root_unlock_time = 60" >> "$fl_conf"
        log_success "Configured pam_faillock settings."
    fi

    # 5.3.3.2 Configure pam_pwquality[cite: 1]
    if ask_yes_no "Configure password complexity (minlen=14, minclass=4, enforce_for_root)? (5.3.3.2)"; then
        local pwq_conf="/etc/security/pwquality.conf"
        sed -i -E 's/^\s*#?\s*minlen\s*=.*/minlen = 14/' "$pwq_conf"
        sed -i -E 's/^\s*#?\s*minclass\s*=.*/minclass = 4/' "$pwq_conf"
        sed -i -E 's/^\s*#?\s*dictcheck\s*=.*/dictcheck = 1/' "$pwq_conf"
        sed -i -E 's/^\s*#?\s*enforce_for_root.*/enforce_for_root/' "$pwq_conf"
        
        # Add if they don't exist
        grep -q "^minlen" "$pwq_conf" || echo "minlen = 14" >> "$pwq_conf"
        grep -q "^minclass" "$pwq_conf" || echo "minclass = 4" >> "$pwq_conf"
        grep -q "^dictcheck" "$pwq_conf" || echo "dictcheck = 1" >> "$pwq_conf"
        grep -q "^enforce_for_root" "$pwq_conf" || echo "enforce_for_root" >> "$pwq_conf"
        log_success "Configured pam_pwquality settings."
    fi

    # 5.3.3.3 Configure pam_pwhistory[cite: 1]
    if ask_yes_no "Configure password history (remember=5, enforce_for_root)? (5.3.3.3)"; then
        local pwh_conf="/etc/security/pwhistory.conf"
        touch "$pwh_conf"
        sed -i -E 's/^\s*#?\s*remember\s*=.*/remember = 5/' "$pwh_conf"
        sed -i -E 's/^\s*#?\s*enforce_for_root.*/enforce_for_root/' "$pwh_conf"
        
        # Add if they don't exist
        grep -q "^remember" "$pwh_conf" || echo "remember = 5" >> "$pwh_conf"
        grep -q "^enforce_for_root" "$pwh_conf" || echo "enforce_for_root" >> "$pwh_conf"
        log_success "Configured pam_pwhistory settings."
    fi

    log_success "PAM configuration applied."
}

run_pam() {
    log_info "Starting CIS Section 5.3: Pluggable Authentication Modules"
    manage_pam
}

register_control "pam" "run_pam"
