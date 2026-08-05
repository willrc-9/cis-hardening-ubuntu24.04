#!/usr/bin/env bash

manage_network_devices() {
    local failed=0

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 3.1.1 Ensure IPv6 status is identified (Manual)
        log_info "Audit Manual Check (3.1.1): Ensure IPv6 status is identified according to site policy."
        if ip a | grep -q 'inet6'; then
            log_info "IPv6 is currently ENABLED on one or more interfaces."
        else
            log_info "IPv6 is currently DISABLED."
        fi

        # 3.1.2 Ensure wireless interfaces are not available
        local wireless_found=0
        if command -v nmcli >/dev/null 2>&1; then
            if nmcli radio wifi 2>/dev/null | grep -q "enabled"; then
                wireless_found=1
            fi
        elif command -v iwconfig >/dev/null 2>&1; then
            if iwconfig 2>/dev/null | grep -q 'IEEE 802.11'; then
                wireless_found=1
            fi
        else
            for dir in /sys/class/net/*/wireless; do
                if [[ -d "$dir" ]]; then
                    wireless_found=1
                    break
                fi
            done
        fi
        
        if [[ $wireless_found -eq 1 ]]; then
            log_warn "Audit Failed (3.1.2): Wireless interfaces are enabled/available."
            failed=1
        fi

        # 3.1.3 Ensure bluetooth services are not in use
        if dpkg -l bluez 2>/dev/null | grep -q "^ii"; then
            log_warn "Audit Failed (3.1.3): 'bluez' (Bluetooth) package is installed."
            failed=1
        fi
        if systemctl is-enabled bluetooth.service 2>/dev/null | grep -q 'enabled' || systemctl is-active bluetooth.service 2>/dev/null | grep -q 'active'; then
            log_warn "Audit Failed (3.1.3): bluetooth.service is enabled or active."
            failed=1
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: Network devices are securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Network Devices (CIS 3.1.x)"

    # 3.1.1 Ensure IPv6 status is identified
    if ask_yes_no "Review current IPv6 status? (CIS 3.1.1 requires manual identification)"; then
        echo "------------------------------------------------------"
        if ip a | grep -q 'inet6'; then
            echo "IPv6 is currently ENABLED. Interfaces with IPv6:"
            ip -6 a
        else
            echo "IPv6 is currently DISABLED."
        fi
        echo "------------------------------------------------------"
        log_success "Manual review of IPv6 status completed."
    fi

    # 3.1.2 Ensure wireless interfaces are not available
    local has_wireless=0
    if command -v nmcli >/dev/null 2>&1 && nmcli radio wifi 2>/dev/null | grep -q "enabled"; then
        has_wireless=1
    elif command -v iwconfig >/dev/null 2>&1 && iwconfig 2>/dev/null | grep -q 'IEEE 802.11'; then
        has_wireless=1
    else
        for dir in /sys/class/net/*/wireless; do
            if [[ -d "$dir" ]]; then
                has_wireless=1
                break
            fi
        done
    fi

    if [[ $has_wireless -eq 1 ]]; then
        if ask_yes_no "Disable wireless interfaces? (3.1.2)"; then
            if command -v nmcli >/dev/null 2>&1; then
                nmcli radio wifi off >/dev/null 2>&1 || true
            fi
            if command -v rfkill >/dev/null 2>&1; then
                rfkill block wifi >/dev/null 2>&1 || true
            fi
            log_success "Disabled wireless interfaces."
        else
            log_info "Skipped disabling wireless interfaces."
        fi
    else
        log_success "No active wireless interfaces detected. (3.1.2 is compliant)"
    fi

    # 3.1.3 Ensure bluetooth services are not in use
    local bt_active=0
    if dpkg -l bluez 2>/dev/null | grep -q "^ii" || systemctl is-enabled bluetooth.service 2>/dev/null | grep -q 'enabled'; then
        bt_active=1
    fi

    if [[ $bt_active -eq 1 ]]; then
        if ask_yes_no "Disable and remove Bluetooth services (bluez)? (3.1.3)"; then
            systemctl stop bluetooth.service >/dev/null 2>&1 || true
            systemctl mask bluetooth.service >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get purge -y bluez >/dev/null 2>&1 || true
            log_success "Disabled and removed Bluetooth services."
        else
            log_info "Skipped removing Bluetooth services."
        fi
    else
        log_success "Bluetooth services are not in use. (3.1.3 is compliant)"
    fi

    log_success "Network devices configuration applied."
}

run_network_devices() {
    log_info "Starting CIS Section 3.1: Configure Network Devices"
    manage_network_devices
}

register_control "network_devices" "run_network_devices"
