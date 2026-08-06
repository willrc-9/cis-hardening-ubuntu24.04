#!/usr/bin/env bash

manage_auditd() {
    local failed=0
    local auditd_conf="/etc/audit/auditd.conf"
    local rules_file="/etc/audit/rules.d/60-cis-hardening.rules"

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 6.2.1.1 Ensure auditd is installed
        if ! dpkg-query -s auditd >/dev/null 2>&1; then
            log_warn "Audit Failed (6.2.1.1): 'auditd' package is not installed."
            failed=1
        fi

        # 6.2.1.2 Ensure auditd service is enabled and active
        if ! systemctl is-enabled auditd.service 2>/dev/null | grep -q 'enabled'; then
            log_warn "Audit Failed (6.2.1.2): auditd.service is not enabled."
            failed=1
        fi
        if ! systemctl is-active auditd.service 2>/dev/null | grep -q 'active'; then
            log_warn "Audit Failed (6.2.1.2): auditd.service is not active."
            failed=1
        fi

        # 6.2.1.3 Configure auditd data retention parameters
        if ! grep -Eq '^\s*max_log_file_action\s*=\s*keep_logs\b' "$auditd_conf" 2>/dev/null; then
            log_warn "Audit Failed (6.2.1.3): max_log_file_action is not set to keep_logs."
            failed=1
        fi
        if ! grep -Eq '^\s*space_left_action\s*=\s*email\b' "$auditd_conf" 2>/dev/null; then
            log_warn "Audit Failed (6.2.1.3): space_left_action is not set to email."
            failed=1
        fi
        if ! grep -Eq '^\s*action_mail_acct\s*=\s*root\b' "$auditd_conf" 2>/dev/null; then
            log_warn "Audit Failed (6.2.1.3): action_mail_acct is not set to root."
            failed=1
        fi
        if ! grep -Eq '^\s*admin_space_left_action\s*=\s*(halt|single)\b' "$auditd_conf" 2>/dev/null; then
            log_warn "Audit Failed (6.2.1.3): admin_space_left_action is not set to halt or single."
            failed=1
        fi

        # 6.2.2.x Audit Rules Checking
        if [[ ! -f "$rules_file" ]]; then
            log_warn "Audit Failed (6.2.2.x): CIS audit rules drop-in file is missing ($rules_file)."
            failed=1
        else
            # 6.2.2.21 Ensure audit configuration is immutable
            if ! grep -Eq '^\s*-e\s+2\b' "$rules_file" 2>/dev/null; then
                log_warn "Audit Failed (6.2.2.21): Audit rules are not set to immutable (-e 2)."
                failed=1
            fi
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: System auditing (auditd) is securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: System Auditing (CIS 6.2.x)"

    # 6.2.1.1 Install auditd
    if ! dpkg-query -s auditd >/dev/null 2>&1; then
        if ask_yes_no "Install 'auditd' package? (6.2.1.1)"; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y auditd audispd-plugins >/dev/null 2>&1
            log_success "Installed auditd."
        else
            log_info "Skipped auditd installation. Cannot proceed with auditing configuration."
            return 0
        fi
    fi

    # 6.2.1.3 Configure auditd data retention
    if ask_yes_no "Configure auditd data retention (keep_logs, email on low space, halt on admin low space)? (6.2.1.3)"; then
        sed -i -E 's/^\s*#?\s*max_log_file_action\s*=.*/max_log_file_action = keep_logs/' "$auditd_conf"
        sed -i -E 's/^\s*#?\s*space_left_action\s*=.*/space_left_action = email/' "$auditd_conf"
        sed -i -E 's/^\s*#?\s*action_mail_acct\s*=.*/action_mail_acct = root/' "$auditd_conf"
        sed -i -E 's/^\s*#?\s*admin_space_left_action\s*=.*/admin_space_left_action = halt/' "$auditd_conf"
        log_success "Configured auditd retention in $auditd_conf."
    fi

    # 6.2.2 Configure audit rules
    if ask_yes_no "Deploy comprehensive CIS audit ruleset to $rules_file? (6.2.2.1 - 6.2.2.20)"; then
        cat << 'EOF' > "$rules_file"
# CIS Ubuntu 24.04 LTS Hardening - Section 6.2.2 Ruleset
# Time modifications
-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time-change
-a always,exit -F arch=b32 -S adjtimex,settimeofday,clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# Identity modifications
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Network environment modifications
-a always,exit -F arch=b64 -S sethostname,setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname,setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network -p wa -k system-locale

# Discretionary Access Control (DAC) modifications
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod

# Unauthorized file access attempts
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access

# Mount operations
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts

# File deletion events
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete

# Sudo scope changes
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# Logins and logouts
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins

# Session initiation
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins
EOF
        log_success "Deployed standard CIS audit ruleset."
    fi

    # 6.2.2.21 Immutability Footgun Warning
    if ask_yes_no "CRITICAL: Make audit configuration immutable? (Requires reboot to modify rules again) (6.2.2.21)"; then
        if ! grep -q '^\s*-e\s+2' "$rules_file"; then
            echo "-e 2" >> "$rules_file"
            log_success "Appended immutability flag (-e 2) to ruleset."
        else
            log_info "Immutability flag already present."
        fi
    else
        sed -i '/^\s*-e\s+2/d' "$rules_file" >/dev/null 2>&1 || true
        log_warn "Skipped immutability. Rules can be updated dynamically."
    fi

    # Enable and restart to apply changes
    if ask_yes_no "Enable and restart auditd to apply rules? (6.2.1.2)"; then
        systemctl enable auditd.service >/dev/null 2>&1
        # auditd often rejects standard systemctl restart commands, so we use augenrules and service
        augenrules --load >/dev/null 2>&1 || true
        service auditd restart >/dev/null 2>&1 || true
        log_success "Enabled and reloaded auditd service."
    fi

    log_success "System auditing configuration applied."
}

run_auditd() {
    log_info "Starting CIS Section 6.2: System Auditing"
    manage_auditd
}

register_control "auditd" "run_auditd"
