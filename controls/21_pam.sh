#!/usr/bin/env bash

manage_pam() {
    local failed=0

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 5.3.1 Ensure PAM software packages are installed
        if ! dpkg-query -s libpam-pwquality >/dev/null 2>&1; then
            log_warn "Audit Failed (5.3.1): 'libpam-pwquality' is not installed."
            failed=1
        fi

        # 5.3.2 Ensure PAM modules are enabled
        local required_profiles=("unix" "faillock" "pwquality" "pwhistory")
        for profile in "${required_profiles[@]}"; do
            if ! grep -q "Name:" "/usr/share/pam-configs/$profile" 2>/dev/null; then
                log_warn "Audit Failed (5.3.2): PAM profile '$profile' is not active/available."
                failed=1
            fi
        done

        # 5.3.3.1 Configure pam_faillock (Lockout policy)
        if ! grep -Eq '^\s*deny\s*=\s*[1-5]\b' /etc/security/faillock.conf 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.1): pam_faillock 'deny' is not set to 5 or less."
            failed=1
        fi
        if ! grep -Eq '^\s*unlock_time\s*=\s*([9-9][0-9]{2}|[1-9][0-9]{3,})\b' /etc/security/faillock.conf 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.1): pam_faillock 'unlock_time' is not configured to 900+ seconds."
            failed=1
        fi

        # 5.3.3.2 Configure pam_pwquality (Password complexity)
        local pwq_files="/etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf"
        
        if ! grep -hEq '^\s*minlen\s*=\s*([1-9][4-9]|[2-9][0-9]+)\b' $pwq_files 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.2.1): pam_pwquality 'minlen' is not 14 or greater."
            failed=1
        fi
        if ! grep -hEq '^\s*minclass\s*=\s*[4-9]\b' $pwq_files 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.2.1): pam_pwquality 'minclass' is not 4 or greater."
            failed=1
        fi
        if ! grep -hEq '^\s*dictcheck\s*=\s*[1-9]\b' $pwq_files 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.2.1): pam_pwquality 'dictcheck' is not enabled (1)."
            failed=1
        fi
        if ! grep -hEq '^\s*enforce_for_root\b' $pwq_files 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.2.1): pam_pwquality 'enforce_for_root' is not configured."
            failed=1
        fi
        if ! grep -hEq '^\s*difok\s*=\s*([2-9]|[1-9][0-9]+)\b' $pwq_files 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.2.1): pam_pwquality 'difok' is not 2 or greater."
            failed=1
        fi
        if ! grep -hEq '^\s*maxrepeat\s*=\s*[1-3]\b' $pwq_files 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.2.1): pam_pwquality 'maxrepeat' is not set to 1-3."
            failed=1
        fi

        # 5.3.3.3 Configure pam_pwhistory (Password history)
        if ! grep -Eq '^\s*remember\s*=\s*([5-9]|[1-9][0-9]+)\b' /etc/security/pwhistory.conf 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.3): pam_pwhistory 'remember' is not 5 or greater in pwhistory.conf."
            failed=1
        fi
        if ! grep -Psiq -- '^\h*password\h+[^#\n\r]+\h+pam_pwhistory\.so\h+([^#\n\r]+\h+)?use_authtok\b' /etc/pam.d/common-password 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.3): pam_pwhistory is missing the 'use_authtok' flag in /etc/pam.d/common-password."
            failed=1
        fi
        if ! grep -Psiq -- '^\h*password\h+[^#\n\r]+\h+pam_pwhistory\.so\h+([^#\n\r]+\h+)?remember=([5-9]|[1-9][0-9]+)\b' /etc/pam.d/common-password 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.3): pam_pwhistory is missing the 'remember' flag in /etc/pam.d/common-password."
            failed=1
        fi

        # 5.3.3.4 Configure pam_unix (CIS 5.3.3.4.1 - 5.3.3.4.4)
        local common_pwd="/etc/pam.d/common-password"
        
        # 5.3.3.4.1 (Negative check: should NOT find nullok)
        if grep -Psiq -- '^\h*password\h+[^#\n\r]+\h+pam_unix\.so\h+([^#\n\r]+\h+)?nullok\b' "$common_pwd" 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.4.1): pam_unix includes insecure 'nullok' flag."
            failed=1
        fi
        # 5.3.3.4.2 (Negative check: should NOT find remember)
        if grep -Psiq -- '^\h*password\h+[^#\n\r]+\h+pam_unix\.so\h+([^#\n\r]+\h+)?remember\b' "$common_pwd" 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.4.2): pam_unix includes 'remember' (should be handled by pwhistory)."
            failed=1
        fi
        # 5.3.3.4.3 (Positive check: MUST find yescrypt or sha512)
        if ! grep -Psiq -- '^\h*password\h+[^#\n\r]+\h+pam_unix\.so\h+([^#\n\r]+\h+)?(yescrypt|sha512)\b' "$common_pwd" 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.4.3): pam_unix is missing a strong hashing algorithm (yescrypt/sha512)."
            failed=1
        fi
        # 5.3.3.4.4 (Positive check: MUST find use_authtok)
        if ! grep -Psiq -- '^\h*password\h+[^#\n\r]+\h+pam_unix\.so\h+([^#\n\r]+\h+)?use_authtok\b' "$common_pwd" 2>/dev/null; then
            log_warn "Audit Failed (5.3.3.4.4): pam_unix is missing the 'use_authtok' flag."
            failed=1
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: PAM is securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Pluggable Authentication Modules (CIS 5.3.x)"

    # 5.3.1 Install libpam-pwquality
    if ! dpkg-query -s libpam-pwquality >/dev/null 2>&1; then
        if ask_yes_no "Install 'libpam-pwquality' to enforce password complexity? (5.3.1)"; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y libpam-pwquality >/dev/null 2>&1
            log_success "Installed libpam-pwquality."
        fi
    fi

    # 5.3.2 Enable PAM profiles
    if ask_yes_no "Enable PAM profiles for faillock, pwquality, and pwhistory? (5.3.2)"; then
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

        cat << 'EOF' > /usr/share/pam-configs/pwhistory
Name: Enforce password history
Default: yes
Priority: 1024
Password-Type: Primary
Password:
	requisite pam_pwhistory.so use_authtok remember=24 enforce_for_root
EOF

        pam-auth-update --enable faillock pwquality pwhistory >/dev/null 2>&1
        log_success "Created and enabled required PAM authentication profiles."
    fi

    # 5.3.3.1 Configure pam_faillock
    if ask_yes_no "Configure account lockout (deny=5, unlock_time=900, even_deny_root)? (5.3.3.1)"; then
        local fl_conf="/etc/security/faillock.conf"
        sed -i -E 's/^\s*#?\s*deny\s*=.*/deny = 5/' "$fl_conf"
        sed -i -E 's/^\s*#?\s*unlock_time\s*=.*/unlock_time = 900/' "$fl_conf"
        sed -i -E 's/^\s*#?\s*even_deny_root.*/even_deny_root/' "$fl_conf"
        sed -i -E 's/^\s*#?\s*root_unlock_time\s*=.*/root_unlock_time = 60/' "$fl_conf"
        
        grep -q "^deny" "$fl_conf" || echo "deny = 5" >> "$fl_conf"
        grep -q "^unlock_time" "$fl_conf" || echo "unlock_time = 900" >> "$fl_conf"
        grep -q "^even_deny_root" "$fl_conf" || echo "even_deny_root" >> "$fl_conf"
        grep -q "^root_unlock_time" "$fl_conf" || echo "root_unlock_time = 60" >> "$fl_conf"
        log_success "Configured pam_faillock settings."
    fi

    # 5.3.3.2 Configure pam_pwquality (Password complexity)
    if ask_yes_no "Configure password complexity (minlen=14, minclass=4, dictcheck, enforce_for_root, difok=2, maxrepeat=3)? (5.3.3.2.1)"; then
        mkdir -p /etc/security/pwquality.conf.d
        local pwq_conf="/etc/security/pwquality.conf.d/60-cis-pwquality.conf"
        
        cat << 'EOF' > "$pwq_conf"
minlen = 14
minclass = 4
dictcheck = 1
enforce_for_root
difok = 2
maxrepeat = 3
ucredit = -2
lcredit = -2
dcredit = -1
ocredit = 0
maxsequence = 3
EOF
        log_success "Configured pam_pwquality settings securely via drop-in file."
    fi

    # 5.3.3.3 Configure pam_pwhistory
    if ask_yes_no "Configure password history (remember=5, enforce_for_root)? (5.3.3.3)"; then
        local pwh_conf="/etc/security/pwhistory.conf"
        touch "$pwh_conf"
        sed -i -E 's/^\s*#?\s*remember\s*=.*/remember = 5/' "$pwh_conf"
        sed -i -E 's/^\s*#?\s*enforce_for_root.*/enforce_for_root/' "$pwh_conf"
        
        grep -q "^remember" "$pwh_conf" || echo "remember = 5" >> "$pwh_conf"
        grep -q "^enforce_for_root" "$pwh_conf" || echo "enforce_for_root" >> "$pwh_conf"
        log_success "Configured pam_pwhistory settings."
    fi

    # 5.3.3.4 Configure pam_unix
    if ask_yes_no "Configure pam_unix (remove nullok/remember, enforce yescrypt and use_authtok)? (5.3.3.4)"; then
        local unix_conf="/usr/share/pam-configs/unix"
        if [[ -f "$unix_conf" ]]; then
            # 1. Globally strip out the insecure/conflicting parameters
            sed -i -E 's/\bnullok_secure\b//g' "$unix_conf"
            sed -i -E 's/\bnullok\b//g' "$unix_conf"
            sed -i -E 's/\bremember=[0-9]+\b//g' "$unix_conf"
            
            # 2. Specifically target the Password block to ensure yescrypt and use_authtok exist
            # This logic appends the parameters safely without breaking the auth phase
            sed -i '/^Password:/,/^$/{
                /\byescrypt\b/! s/pam_unix\.so/pam_unix.so yescrypt/
                /\buse_authtok\b/! s/pam_unix\.so/pam_unix.so use_authtok/
            }' "$unix_conf"
            
            # 3. Force pam-auth-update to write these changes into the live /etc/pam.d/ files
            pam-auth-update --enable unix >/dev/null 2>&1
            log_success "Configured and applied pam_unix settings."
        else
            log_warn "Could not find $unix_conf. PAM unix configuration skipped."
        fi
    fi

    log_success "PAM configuration applied."
}

run_pam() {
    log_info "Starting CIS Section 5.3: Pluggable Authentication Modules"
    manage_pam
}

register_control "pam" "run_pam"
