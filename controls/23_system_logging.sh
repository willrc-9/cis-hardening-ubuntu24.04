#!/usr/bin/env bash

manage_system_logging() {
    local failed=0
    local journald_conf="/etc/systemd/journald.conf"
    local rsyslog_conf="/etc/rsyslog.conf"

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 6.1.1.1.1 Ensure journald service is active[cite: 1]
        if ! systemctl is-active systemd-journald.service 2>/dev/null | grep -q 'active'; then
            log_warn "Audit Failed (6.1.1.1.1): systemd-journald is not active."
            failed=1
        fi

        # 6.1.1.1.2 Ensure systemd-journal-remote is not in use[cite: 1]
        if systemctl is-enabled systemd-journal-remote.socket 2>/dev/null | grep -q 'enabled'; then
            log_warn "Audit Failed (6.1.1.1.2): systemd-journal-remote.socket is enabled."
            failed=1
        fi

        # 6.1.1.1.3 Ensure journald is configured to send logs to rsyslog[cite: 1]
        if ! grep -Eq '^\s*ForwardToSyslog=yes\b' "$journald_conf" 2>/dev/null; then
            log_warn "Audit Failed (6.1.1.1.3): journald ForwardToSyslog is not set to yes."
            failed=1
        fi

        # 6.1.1.1.6 Ensure journald Storage is configured[cite: 1]
        if ! grep -Eq '^\s*Storage=persistent\b' "$journald_conf" 2>/dev/null; then
            log_warn "Audit Failed (6.1.1.1.6): journald Storage is not set to persistent."
            failed=1
        fi

        # 6.1.1.1.7 Ensure journald Compress is configured[cite: 1]
        if ! grep -Eq '^\s*Compress=yes\b' "$journald_conf" 2>/dev/null; then
            log_warn "Audit Failed (6.1.1.1.7): journald Compress is not set to yes."
            failed=1
        fi

        # 6.1.2.1 & 6.1.2.2 Ensure rsyslog is installed and active[cite: 1]
        if ! dpkg-query -s rsyslog >/dev/null 2>&1; then
            log_warn "Audit Failed (6.1.2.1): 'rsyslog' is not installed."
            failed=1
        elif ! systemctl is-active rsyslog.service 2>/dev/null | grep -q 'active'; then
            log_warn "Audit Failed (6.1.2.2): rsyslog is installed but not active."
            failed=1
        fi

        # 6.1.2.3 Ensure rsyslog log file creation mode is configured[cite: 1]
        if ! grep -Eq '^\s*\$FileCreateMode\s+0640\b' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null; then
            log_warn "Audit Failed (6.1.2.3): rsyslog \$FileCreateMode is not configured to 0640."
            failed=1
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: System logging (journald/rsyslog) is securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: System Logging (CIS 6.1.x)"

    # 6.1.1 Configure journald[cite: 1]
    if ask_yes_no "Configure journald settings (Storage=persistent, Compress=yes, ForwardToSyslog=yes)? (6.1.1)"; then
        sed -i -E 's/^\s*#?\s*Storage=.*/Storage=persistent/' "$journald_conf"
        sed -i -E 's/^\s*#?\s*Compress=.*/Compress=yes/' "$journald_conf"
        sed -i -E 's/^\s*#?\s*ForwardToSyslog=.*/ForwardToSyslog=yes/' "$journald_conf"
        
        # Append parameters if they do not exist
        grep -q "^Storage=" "$journald_conf" || echo "Storage=persistent" >> "$journald_conf"
        grep -q "^Compress=" "$journald_conf" || echo "Compress=yes" >> "$journald_conf"
        grep -q "^ForwardToSyslog=" "$journald_conf" || echo "ForwardToSyslog=yes" >> "$journald_conf"
        
        systemctl restart systemd-journald >/dev/null 2>&1
        log_success "Configured and restarted journald."
    fi

    # 6.1.1.1.2 Ensure systemd-journal-remote is not in use[cite: 1]
    if systemctl is-active systemd-journal-remote.socket >/dev/null 2>&1 || systemctl is-enabled systemd-journal-remote.socket >/dev/null 2>&1; then
        if ask_yes_no "Disable systemd-journal-remote.socket to prevent unauthorized remote log reception? (6.1.1.1.2)"; then
            systemctl stop systemd-journal-remote.socket systemd-journal-remote.service >/dev/null 2>&1 || true
            systemctl mask systemd-journal-remote.socket systemd-journal-remote.service >/dev/null 2>&1 || true
            log_success "Disabled and masked systemd-journal-remote."
        fi
    fi

    # 6.1.2 Configure rsyslog[cite: 1]
    if ! dpkg-query -s rsyslog >/dev/null 2>&1; then
        if ask_yes_no "Install 'rsyslog' package? (6.1.2.1)"; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y rsyslog >/dev/null 2>&1
            log_success "Installed rsyslog."
        fi
    fi

    if dpkg-query -s rsyslog >/dev/null 2>&1; then
        if ask_yes_no "Enable rsyslog and set default FileCreateMode to 0640? (6.1.2.2, 6.1.2.3)"; then
            systemctl enable rsyslog >/dev/null 2>&1
            systemctl start rsyslog >/dev/null 2>&1
            
            # Configure FileCreateMode[cite: 1]
            if grep -Eq '^\s*\$FileCreateMode' "$rsyslog_conf"; then
                sed -i -E 's/^\s*\$FileCreateMode.*/$FileCreateMode 0640/' "$rsyslog_conf"
            else
                # Insert at the very top of the file
                sed -i '1i $FileCreateMode 0640' "$rsyslog_conf"
            fi
            
            systemctl restart rsyslog >/dev/null 2>&1
            log_success "Configured and restarted rsyslog."
        fi
    fi

    log_success "System logging configuration applied."
}

run_system_logging() {
    log_info "Starting CIS Section 6.1: System Logging"
    manage_system_logging
}

register_control "system_logging" "run_system_logging"
