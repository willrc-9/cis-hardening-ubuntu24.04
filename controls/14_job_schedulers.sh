#!/usr/bin/env bash

manage_job_schedulers() {
    local failed=0

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 2.4.1.1 Ensure cron daemon is enabled and active
        if ! systemctl is-enabled cron 2>/dev/null | grep -q 'enabled' || ! systemctl is-active cron 2>/dev/null | grep -q 'active'; then
            log_warn "Audit Failed (2.4.1.1): cron daemon is not enabled and active."
            failed=1
        else
            log_success "Audit Passed (2.4.1.1): cron daemon is enabled and active."
        fi

        # 2.4.1.2 Ensure access to /etc/crontab is configured
        if [[ -f /etc/crontab ]]; then
            local crontab_stat
            crontab_stat="$(stat -c "%a %U %G" /etc/crontab)"
            if [[ "$crontab_stat" != "600 root root" && "$crontab_stat" != "400 root root" && "$crontab_stat" != "000 root root" ]]; then
                log_warn "Audit Failed (2.4.1.2): /etc/crontab permissions ($crontab_stat) are not 600 or more restrictive, or not root:root."
                failed=1
            fi
        fi

        # 2.4.1.3 - 2.4.1.8 Ensure permissions on cron directories (/etc/cron.hourly, daily, weekly, monthly, yearly, d)
        local cron_dirs=("/etc/cron.hourly" "/etc/cron.daily" "/etc/cron.weekly" "/etc/cron.monthly" "/etc/cron.yearly" "/etc/cron.d")
        for dir in "${cron_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                local dir_stat
                dir_stat="$(stat -c "%a %U %G" "$dir")"
                # Accept 700, 500, 300, 100, 000 root root
                if [[ "$dir_stat" != "700 root root" && "$dir_stat" != "500 root root" && "$dir_stat" != "300 root root" && "$dir_stat" != "100 root root" && "$dir_stat" != "000 root root" ]]; then
                    log_warn "Audit Failed (2.4.1.x): $dir permissions ($dir_stat) or ownership are not 700 root:root."
                    failed=1
                fi
            fi
        done

        # 2.4.1.9 Ensure cron is restricted to authorized users (/etc/cron.allow and no cron.deny)
        if [[ -e /etc/cron.deny ]]; then
            log_warn "Audit Failed (2.4.1.9): /etc/cron.deny exists. System should use an allow-list."
            failed=1
        fi
        if [[ -f /etc/cron.allow ]]; then
            local cron_allow_stat
            cron_allow_stat="$(stat -c "%a %U %G" /etc/cron.allow)"
            if [[ "$cron_allow_stat" != "600 root root" && "$cron_allow_stat" != "400 root root" && "$cron_allow_stat" != "640 root root" ]]; then
                log_warn "Audit Failed (2.4.1.9): /etc/cron.allow permissions or ownership are incorrect."
                failed=1
            fi
        else
            log_warn "Audit Failed (2.4.1.9): /etc/cron.allow does not exist."
            failed=1
        fi

        # 2.4.2.1 Ensure access to at is configured
        if dpkg -l at 2>/dev/null | grep -q "^ii"; then
            if [[ -e /etc/at.deny ]]; then
                log_warn "Audit Failed (2.4.2.1): /etc/at.deny exists. System should use an allow-list."
                failed=1
            fi
            if [[ -f /etc/at.allow ]]; then
                local at_allow_stat
                at_allow_stat="$(stat -c "%a %U %G" /etc/at.allow)"
                if [[ "$at_allow_stat" != "600 root root" && "$at_allow_stat" != "400 root root" && "$at_allow_stat" != "640 root root" ]]; then
                    log_warn "Audit Failed (2.4.2.1): /etc/at.allow permissions or ownership are incorrect."
                    failed=1
                fi
            else
                log_warn "Audit Failed (2.4.2.1): /etc/at.allow does not exist."
                failed=1
            fi
        else
            log_success "Audit Passed (2.4.2.1): 'at' package is not installed (Not Applicable)."
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: Job schedulers are securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Job Schedulers (CIS 2.4.x)"

    if ask_yes_no "Ensure cron daemon is enabled and active? (2.4.1.1)"; then
        systemctl enable cron >/dev/null 2>&1 || true
        systemctl start cron >/dev/null 2>&1 || true
        log_success "Enabled and started cron service."
    fi

    if ask_yes_no "Secure permissions for /etc/crontab and all cron configuration directories? (2.4.1.2 - 2.4.1.8)"; then
        if [[ -f /etc/crontab ]]; then
            chown root:root /etc/crontab
            chmod 600 /etc/crontab
        fi
        
        local cron_dirs=("/etc/cron.hourly" "/etc/cron.daily" "/etc/cron.weekly" "/etc/cron.monthly" "/etc/cron.yearly" "/etc/cron.d")
        for dir in "${cron_dirs[@]}"; do
            mkdir -p "$dir"
            chown root:root "$dir"
            chmod 700 "$dir"
        done
        log_success "Secured cron file and directory permissions."
    fi

    if ask_yes_no "Restrict cron to authorized users via /etc/cron.allow and remove /etc/cron.deny? (2.4.1.9)"; then
        rm -f /etc/cron.deny
        touch /etc/cron.allow
        chown root:root /etc/cron.allow
        chmod 600 /etc/cron.allow
        log_success "Restricted cron usage to allow-list only."
    fi

    if dpkg -l at 2>/dev/null | grep -q "^ii"; then
        if ask_yes_no "Restrict 'at' daemon to authorized users via /etc/at.allow and remove /etc/at.deny? (2.4.2.1)"; then
            rm -f /etc/at.deny
            touch /etc/at.allow
            chown root:root /etc/at.allow
            chmod 600 /etc/at.allow
            log_success "Restricted 'at' usage to allow-list only."
        fi
    else
        log_info "Skipped configuring 'at' because the package is not installed."
    fi

    log_success "Job schedulers configuration applied."
}

run_job_schedulers() {
    log_info "Starting CIS Section 2.4: Configure Job Schedulers"
    manage_job_schedulers
}

register_control "job_schedulers" "run_job_schedulers"
