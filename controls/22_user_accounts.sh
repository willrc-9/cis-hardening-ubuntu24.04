#!/usr/bin/env bash

manage_user_accounts() {
    local failed=0

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 5.4.1.1 - 5.4.1.4 Shadow password suite parameters[cite: 1]
        if ! grep -Eq '^\s*PASS_MAX_DAYS\s+([1-9]|[1-9][0-9]|[1-2][0-9]{2}|3[0-5][0-9]|36[0-5])\b' /etc/login.defs; then
            log_warn "Audit Failed (5.4.1.1): PASS_MAX_DAYS is not set to 365 or less."
            failed=1
        fi
        if ! grep -Eq '^\s*PASS_MIN_DAYS\s+([1-9]|[1-9][0-9]+)\b' /etc/login.defs; then
            log_warn "Audit Failed (5.4.1.2): PASS_MIN_DAYS is not set to 1 or greater."
            failed=1
        fi
        if ! grep -Eq '^\s*PASS_WARN_AGE\s+([7-9]|[1-9][0-9]+)\b' /etc/login.defs; then
            log_warn "Audit Failed (5.4.1.3): PASS_WARN_AGE is not set to 7 or greater."
            failed=1
        fi
        if ! grep -Eq '^\s*ENCRYPT_METHOD\s+(YESCRYPT|SHA512)\b' /etc/login.defs; then
            log_warn "Audit Failed (5.4.1.4): ENCRYPT_METHOD is not YESCRYPT or SHA512."
            failed=1
        fi

        # 5.4.1.5 Ensure inactive password lock is configured[cite: 1]
        if ! useradd -D | grep -Eq 'INACTIVE=([1-9]|[1-2][0-9]|30)\b'; then
            log_warn "Audit Failed (5.4.1.5): Default useradd INACTIVE is not 30 or less."
            failed=1
        fi

        # 5.4.2.1 Ensure root is the only UID 0 account[cite: 1]
        if awk -F: '$3 == 0 {print $1}' /etc/passwd | grep -vq '^root$'; then
            log_warn "Audit Failed (5.4.2.1): Non-root accounts with UID 0 exist."
            failed=1
        fi

        # 5.4.2.4 Ensure root account access is controlled[cite: 1]
        if ! passwd -S root | awk '{print $2}' | grep -Eq '^(L|LK|\*)$'; then
            log_warn "Audit Failed (5.4.2.4): Root account is not locked."
            failed=1
        fi

        # 5.4.3.1 Ensure nologin is not listed in /etc/shells[cite: 1]
        if grep -Eq 'nologin' /etc/shells; then
            log_warn "Audit Failed (5.4.3.1): nologin is listed in /etc/shells."
            failed=1
        fi

        # 5.4.3.2 Ensure default user shell timeout is configured[cite: 1]
        # Updated regex to account for the 'readonly' or 'export' prefix
        if ! grep -Eq '^\s*(readonly\s+|export\s+)?TMOUT=(900|[1-8][0-9]{2}|[1-9][0-9]|[1-9])\b' /etc/profile.d/*.sh /etc/profile /etc/bash.bashrc 2>/dev/null; then
            log_warn "Audit Failed (5.4.3.2): TMOUT is not configured to 900 or less."
            failed=1
        fi

        # 5.4.3.3 Ensure default user umask is configured[cite: 1]
        if ! grep -Eq '^\s*UMASK\s+027\b' /etc/login.defs; then
            log_warn "Audit Failed (5.4.3.3): UMASK is not set to 027 in /etc/login.defs."
            failed=1
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: User accounts and environment are securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: User Accounts and Environment (CIS 5.4.x)"

    # 5.4.1 Configure shadow password suite parameters[cite: 1]
    if ask_yes_no "Configure strict password expiration defaults (MAX=365, MIN=1, WARN=7, YESCRYPT)? (5.4.1)"; then
        sed -i -E 's/^\s*PASS_MAX_DAYS.*/PASS_MAX_DAYS 365/' /etc/login.defs
        sed -i -E 's/^\s*PASS_MIN_DAYS.*/PASS_MIN_DAYS 1/' /etc/login.defs
        sed -i -E 's/^\s*PASS_WARN_AGE.*/PASS_WARN_AGE 7/' /etc/login.defs
        
        if grep -q "ENCRYPT_METHOD" /etc/login.defs; then
            sed -i -E 's/^\s*ENCRYPT_METHOD.*/ENCRYPT_METHOD YESCRYPT/' /etc/login.defs
        else
            echo "ENCRYPT_METHOD YESCRYPT" >> /etc/login.defs
        fi

        # 5.4.1.5 Inactive lock (30 days)[cite: 1]
        useradd -D -f 30 >/dev/null 2>&1
        log_success "Configured password expiration and inactive lock defaults."
    fi

    # 5.4.2 Root and System accounts[cite: 1]
    if ask_yes_no "Lock the root account and secure system accounts? (5.4.2)"; then
        # 5.4.2.4 Lock root[cite: 1]
        passwd -l root >/dev/null 2>&1
        log_success "Locked root account password."

        # 5.4.2.7 & 5.4.2.8 Ensure system accounts do not have a valid login shell and are locked[cite: 1]
        for user in $(awk -F: '$3 < 1000 && $1 != "root" && $1 != "sync" && $1 != "shutdown" && $1 != "halt" {print $1}' /etc/passwd); do
            usermod -L "$user" >/dev/null 2>&1 || true
            if [[ $(awk -F: -v u="$user" '$1 == u {print $7}' /etc/passwd) != "/usr/sbin/nologin" && $(awk -F: -v u="$user" '$1 == u {print $7}' /etc/passwd) != "/bin/false" ]]; then
                usermod -s /usr/sbin/nologin "$user" >/dev/null 2>&1 || true
            fi
        done
        log_success "Secured shells and locked passwords for system accounts."
    fi

    # 5.4.3 Configure user default environment[cite: 1]
    if ask_yes_no "Configure user default environment (TMOUT=900, UMASK=027, remove nologin from shells)? (5.4.3)"; then
        # 5.4.3.1 Remove nologin from shells[cite: 1]
        sed -i '/nologin/d' /etc/shells
        
        # 5.4.3.2 Default user shell timeout[cite: 1]
        local tmout_file="/etc/profile.d/60-tmout.sh"
        echo "readonly TMOUT=900" > "$tmout_file"
        echo "export TMOUT" >> "$tmout_file"
        chmod 0644 "$tmout_file"

        # 5.4.3.3 Default user umask[cite: 1]
        sed -i -E 's/^\s*UMASK.*/UMASK 027/' /etc/login.defs
        if ! grep -q "^UMASK" /etc/login.defs; then
            echo "UMASK 027" >> /etc/login.defs
        fi
        sed -i -E 's/^\s*USERGROUPS_ENAB.*/USERGROUPS_ENAB yes/' /etc/login.defs

        local umask_file="/etc/profile.d/60-umask.sh"
        echo "umask 027" > "$umask_file"
        chmod 0644 "$umask_file"

        log_success "Configured user default environment settings."
    fi

    log_success "User Accounts and Environment configuration applied."
}

run_user_accounts() {
    log_info "Starting CIS Section 5.4: User Accounts and Environment"
    manage_user_accounts
}

register_control "user_accounts" "run_user_accounts"
