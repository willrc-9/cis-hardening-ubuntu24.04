#!/usr/bin/env bash

service_check() {
    local service_name="$1"
    local output=""
    if systemctl is-enabled -q "$service_name" 2>/dev/null; then
        output="$output\n - Daemon: \"$service_name\" is enabled on the system"
    else
        output="$output\n - Daemon: \"$service_name\" is not enabled on the system"
    fi
    if systemctl is-active -q "$service_name" 2>/dev/null; then
        output="$output\n - Daemon: \"$service_name\" is active on the system"
    else
        output="$output\n - Daemon: \"$service_name\" is not active on the system"
    fi
    echo -e "$output"
}

manage_time_sync() {
    local failed=0
    local timesyncd_conf="/etc/systemd/timesyncd.conf"
    local chrony_conf="/etc/chrony/chrony.conf"
    local chrony_default="/etc/default/chrony"
    
    # Define your enterprise time servers here
    local primary_ntp="ntp.ubuntu.com"
    local fallback_ntp="0.pool.ntp.org 1.pool.ntp.org"

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        local sync_in_use=0
        local timesyncd_active=0
        local chrony_active=0
        
        # 1. Check chrony FIRST (2.3.3)
        if systemctl is-enabled -q chrony 2>/dev/null || systemctl is-active -q chrony 2>/dev/null; then
            sync_in_use=1
            chrony_active=1
            if ! grep -E -q '^(server|pool)' "$chrony_conf" 2>/dev/null; then
                log_warn "Audit Failed (2.3.3): chrony is enabled but no server/pool is configured in $chrony_conf"
                failed=1
            fi
            # Relaxed the regex to ignore quote types
            if ! grep -E -q 'DAEMON_OPTS=.*-u _chrony' "$chrony_default" 2>/dev/null; then
                log_warn "Audit Failed (2.3.3): chrony is not running as the _chrony user via DAEMON_OPTS in $chrony_default"
                failed=1
            fi
            if [[ $failed -eq 0 ]]; then
                log_success "Audit Passed (2.3.3): chrony is correctly configured."
            fi
        fi

        # 2. Check systemd-timesyncd SECOND (2.3.2)
        if systemctl is-enabled -q systemd-timesyncd 2>/dev/null || systemctl is-active -q systemd-timesyncd 2>/dev/null; then
            sync_in_use=1
            timesyncd_active=1
            # Requires BOTH NTP and FallbackNTP to be uncommented
            if ! grep -q "^NTP=" "$timesyncd_conf" 2>/dev/null || ! grep -q "^FallbackNTP=" "$timesyncd_conf" 2>/dev/null; then
                log_warn "Audit Failed (2.3.2): systemd-timesyncd is enabled but NTP/FallbackNTP is not explicitly configured."
                failed=1
            else
                log_success "Audit Passed (2.3.2): systemd-timesyncd is correctly configured."
            fi
        fi

        # Evaluate the mutually exclusive rule (2.3.1)
        if [[ $sync_in_use -eq 0 ]]; then
            log_warn "Audit Failed (2.3.1): Neither daemon is enabled. (Expected if using host-based virtualization sync)."
            failed=1
        elif [[ $timesyncd_active -eq 1 && $chrony_active -eq 1 ]]; then
            log_warn "Audit Failed (2.3.1): BOTH systemd-timesyncd and chrony are active. Only ONE must be used."
            failed=1
        else
            log_success "Audit Passed (2.3.1): A single time synchronization daemon is in use."
            
            if [[ $timesyncd_active -eq 1 ]]; then
                log_success "Audit Passed (2.3.3): chrony is not in use. Control is Not Applicable."
            elif [[ $chrony_active -eq 1 ]]; then
                log_success "Audit Passed (2.3.2): systemd-timesyncd is not in use. Control is Not Applicable."
            fi
        fi

        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Time Synchronization (CIS 2.3.x)"
    
    echo "--------------------------------------------------------------------------------"
    echo "CIS NOTE (2.3.1.1): On virtual systems where host based time synchronization is"
    echo "available, consult your virtualization software documentation."
    echo ""
    echo "Current Configuration:"
    service_check chrony.service
    service_check systemd-timesyncd.service
    echo "--------------------------------------------------------------------------------"

    if ask_yes_no "Are you using host-based time synchronization for this machine? (Select 'y' to SKIP)"; then
        log_info "Skipping time synchronization configuration."
        return 0
    fi

    local sync_choice=""
    while true; do
        # Swapped menu order to prioritize Chrony
        read -r -p "Select daemon to configure - [1] chrony (Recommended) or [2] systemd-timesyncd: " sync_choice
        case "$sync_choice" in
            1)
                log_info "Configuring chrony..."
                DEBIAN_FRONTEND=noninteractive apt-get install -y chrony >/dev/null 2>&1 || true
                systemctl unmask chrony >/dev/null 2>&1 || true
                
                cp -n "$chrony_conf" "${chrony_conf}.bak" 2>/dev/null || true
                cp -n "$chrony_default" "${chrony_default}.bak" 2>/dev/null || true
                
                if ! grep -E -q '^(server|pool)' "$chrony_conf" 2>/dev/null; then
                    echo "pool $primary_ntp iburst maxsources 4" >> "$chrony_conf"
                    echo "pool $fallback_ntp iburst maxsources 1" >> "$chrony_conf"
                fi
                
                if [[ -f "$chrony_default" ]]; then
                    if grep -q '^DAEMON_OPTS=' "$chrony_default"; then
                        if ! grep -q -- '-u _chrony' "$chrony_default"; then
                            sed -i 's/^DAEMON_OPTS="\(.*\)"/DAEMON_OPTS="-u _chrony \1"/' "$chrony_default"
                        fi
                    else
                        echo 'DAEMON_OPTS="-u _chrony"' >> "$chrony_default"
                    fi
                fi
                
                if dpkg -l systemd-timesyncd 2>/dev/null | grep -q "^ii"; then
                    systemctl stop systemd-timesyncd >/dev/null 2>&1 || true
                    systemctl mask systemd-timesyncd >/dev/null 2>&1 || true
                    log_success "Masked conflicting systemd-timesyncd service."
                fi
                
                systemctl restart chrony >/dev/null 2>&1 || true
                systemctl enable chrony >/dev/null 2>&1 || true
                log_success "Configured and enabled chrony."
                break
                ;;
            2)
                log_info "Configuring systemd-timesyncd..."
                DEBIAN_FRONTEND=noninteractive apt-get install -y systemd-timesyncd >/dev/null 2>&1 || true
                systemctl unmask systemd-timesyncd >/dev/null 2>&1 || true
                
                if [[ -f "$timesyncd_conf" ]]; then
                    cp -n "$timesyncd_conf" "${timesyncd_conf}.bak" 2>/dev/null || true
                    
                    # Bulletproof sed logic
                    if grep -q "^NTP=" "$timesyncd_conf"; then
                        sed -i "s|^NTP=.*|NTP=$primary_ntp|" "$timesyncd_conf"
                    elif grep -q "^#NTP=" "$timesyncd_conf"; then
                        sed -i "s|^#NTP=.*|NTP=$primary_ntp|" "$timesyncd_conf"
                    else
                        echo "NTP=$primary_ntp" >> "$timesyncd_conf"
                    fi

                    if grep -q "^FallbackNTP=" "$timesyncd_conf"; then
                        sed -i "s|^FallbackNTP=.*|FallbackNTP=$fallback_ntp|" "$timesyncd_conf"
                    elif grep -q "^#FallbackNTP=" "$timesyncd_conf"; then
                        sed -i "s|^#FallbackNTP=.*|FallbackNTP=$fallback_ntp|" "$timesyncd_conf"
                    else
                        echo "FallbackNTP=$fallback_ntp" >> "$timesyncd_conf"
                    fi
                fi
                
                if dpkg -l chrony 2>/dev/null | grep -q "^ii"; then
                    systemctl stop chrony >/dev/null 2>&1 || true
                    systemctl mask chrony >/dev/null 2>&1 || true
                    log_success "Masked conflicting chrony service."
                fi
                
                systemctl restart systemd-timesyncd >/dev/null 2>&1 || true
                systemctl enable systemd-timesyncd >/dev/null 2>&1 || true
                log_success "Configured and enabled systemd-timesyncd."
                break
                ;;
            *)
                echo "Invalid selection. Please enter 1 or 2."
                ;;
        esac
    done

    log_success "Time synchronization configuration applied."
}

run_time_sync() {
    log_info "Starting CIS Section 2.3: Configure Time Synchronization"
    manage_time_sync
}

register_control "time_sync" "run_time_sync"
