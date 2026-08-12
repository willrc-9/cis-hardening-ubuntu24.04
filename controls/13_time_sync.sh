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

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        local sync_in_use=0
        local timesyncd_active=0
        local chrony_active=0
        
        # Check systemd-timesyncd (2.3.2)
        if systemctl is-enabled systemd-timesyncd 2>/dev/null | grep -q 'enabled' || systemctl is-active systemd-timesyncd 2>/dev/null | grep -q 'active'; then
            sync_in_use=1
            timesyncd_active=1
            if ! grep -E -q '^(Fallback)?NTP=' "$timesyncd_conf" 2>/dev/null; then
                log_warn "Audit Failed (2.3.2): systemd-timesyncd is enabled but NTP/FallbackNTP is not configured in $timesyncd_conf"
                failed=1
            else
                log_success "Audit Passed (2.3.2): systemd-timesyncd is correctly configured."
            fi
        fi

        # Check chrony (2.3.3)
        if systemctl is-enabled chrony 2>/dev/null | grep -q 'enabled' || systemctl is-active chrony 2>/dev/null | grep -q 'active'; then
            sync_in_use=1
            chrony_active=1
            if ! grep -E -q '^(server|pool)' "$chrony_conf" 2>/dev/null; then
                log_warn "Audit Failed (2.3.3): chrony is enabled but no server/pool is configured in $chrony_conf"
                failed=1
            fi
            if ! grep -E -q 'DAEMON_OPTS=".*-u _chrony.*"' "$chrony_default" 2>/dev/null; then
                log_warn "Audit Failed (2.3.3): chrony is not running as the _chrony user via DAEMON_OPTS in $chrony_default"
                failed=1
            fi
            # Only log success for chrony if no sub-checks failed
            if [[ $failed -eq 0 ]]; then
                log_success "Audit Passed (2.3.3): chrony is correctly configured."
            fi
        fi

        # Evaluate the mutually exclusive rule (2.3.1)
        if [[ $sync_in_use -eq 0 ]]; then
            log_warn "Audit Failed (2.3.1): Neither systemd-timesyncd nor chrony is enabled. (Note: If using hypervisor/host-based time sync, this failure is expected and can be manually documented)."
            failed=1
        elif [[ $timesyncd_active -eq 1 && $chrony_active -eq 1 ]]; then
            log_warn "Audit Failed (2.3.1): BOTH systemd-timesyncd and chrony are active. Only ONE must be used to prevent conflicts."
            log_info "Please refer to /cis-hardening-ubuntu24.04/help/time_sync_help.txt for information on removing either chrony or timesyncd"
	    failed=1
        else
            log_success "Audit Passed (2.3.1): A single time synchronization daemon is in use."
            
            # Explicitly mark the unused daemon as a pass (Not Applicable)
            if [[ $timesyncd_active -eq 1 ]]; then
                log_success "Audit Passed (2.3.3): chrony is not in use (systemd-timesyncd is handling time). Control is Not Applicable."
            elif [[ $chrony_active -eq 1 ]]; then
                log_success "Audit Passed (2.3.2): systemd-timesyncd is not in use (chrony is handling time). Control is Not Applicable."
            fi
        fi

        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Time Synchronization (CIS 2.3.x)"
    
    # CIS 2.3.1.1 Note regarding virtual systems
    echo "--------------------------------------------------------------------------------"
    echo "CIS NOTE (2.3.1.1): On virtual systems where host based time synchronization is"
    echo "available, consult your virtualization software documentation and verify that"
    echo "host based synchronization is in use and follows local site policy."
    echo "In this scenario, this section should be skipped."
    echo ""
    echo "Only ONE time synchronization method should be in use on the system."
    echo "Configuring multiple methods could lead to unexpected or unreliable results."
    echo ""
    echo ""
    echo "Current Configuration:"
    service_check chrony.service
    service_check systemd-timesyncd.service
    echo "--------------------------------------------------------------------------------"

    if ask_yes_no "Are you using host-based time synchronization for this machine? (Select 'y' to SKIP this section)"; then
        log_info "Skipping time synchronization configuration due to host-based synchronization."
        return 0
    fi

    # Force a strict choice between the two supported daemons
    local sync_choice=""
    while true; do
        read -r -p "Select time synchronization daemon to configure - [1] systemd-timesyncd (Default) or [2] chrony: " sync_choice
        case "$sync_choice" in
            1)
                log_info "Configuring systemd-timesyncd..."
                DEBIAN_FRONTEND=noninteractive apt-get install -y systemd-timesyncd >/dev/null 2>&1 || true
                systemctl unmask systemd-timesyncd >/dev/null 2>&1 || true
                
                if [[ -f "$timesyncd_conf" ]]; then
                    backup_file "$timesyncd_conf" 2>/dev/null || true
                    sed -i 's/^#NTP=/NTP=ntp.ubuntu.com/' "$timesyncd_conf"
                    sed -i 's/^#FallbackNTP=/FallbackNTP=ntp.ubuntu.com pool.ntp.org/' "$timesyncd_conf"
                fi
                
                # Actively destroy the alternative to prevent conflicts
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
            2)
                log_info "Configuring chrony..."
                DEBIAN_FRONTEND=noninteractive apt-get install -y chrony >/dev/null 2>&1 || true
                systemctl unmask chrony >/dev/null 2>&1 || true
                
                backup_file "$chrony_conf" 2>/dev/null || true
                backup_file "$chrony_default" 2>/dev/null || true
                
                if ! grep -E -q '^(server|pool)' "$chrony_conf" 2>/dev/null; then
                    echo "pool ntp.ubuntu.com iburst maxsources 4" >> "$chrony_conf"
                    echo "pool 0.ubuntu.pool.ntp.org iburst maxsources 1" >> "$chrony_conf"
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
                
                # Actively destroy the alternative to prevent conflicts
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
