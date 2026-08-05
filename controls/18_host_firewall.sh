#!/usr/bin/env bash

manage_host_firewall() {
    local failed=0
    
    echo "-----------------------------------------------------------------------------------------------------------------------"
    echo ""
    echo ""
    log_info "MAKE SURE TO ADD DESIRED PORTS TO THE CONFIG FILE IN /cis-hardening-ubuntu24.04/config.conf OR THEY WILL BE BLOCKED"
    echo ""
    echo ""
    echo "-----------------------------------------------------------------------------------------------------------------------"
    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 4.1.1 Ensure ufw is installed
        if ! dpkg-query -s ufw >/dev/null 2>&1; then
            log_warn "Audit Failed (4.1.1): 'ufw' package is not installed."
            failed=1
        fi

        # 4.1.2 Ensure ufw service is configured (enabled and active)
        if ! systemctl is-enabled ufw.service 2>/dev/null | grep -q 'enabled'; then
            log_warn "Audit Failed (4.1.2): ufw.service is not enabled."
            failed=1
        fi
        if ! ufw status 2>/dev/null | grep -q "Status: active"; then
            log_warn "Audit Failed (4.1.2): UFW is not active."
            failed=1
        fi

        # Extract UFW default policies
        local ufw_defaults
        ufw_defaults=$(ufw status verbose 2>/dev/null | grep "Default:")

        # 4.1.3 Ensure ufw incoming default is configured
        if ! echo "$ufw_defaults" | grep -Eq "(deny|reject) \(incoming\)"; then
            log_warn "Audit Failed (4.1.3): UFW default incoming policy is not deny or reject."
            failed=1
        fi

        # 4.1.4 Ensure ufw outgoing default is configured
        if ! echo "$ufw_defaults" | grep -Eq "(allow|deny|reject) \(outgoing\)"; then
            log_warn "Audit Failed (4.1.4): UFW default outgoing policy is not securely configured."
            failed=1
        fi

        # 4.1.5 Ensure ufw routed default is configured
        # Accept 'disabled' as a pass, as it occurs when kernel IP forwarding is turned off
        if ! echo "$ufw_defaults" | grep -Eq "(deny|reject|disabled) \(routed\)"; then
            log_warn "Audit Failed (4.1.5): UFW default routed (forwarding) policy is not deny, reject, or disabled."
            failed=1
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: UFW firewall is securely configured and active."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Host Based Firewall (CIS 4.1.x)"

    # 4.1.1 Ensure ufw is installed
    if ! dpkg-query -s ufw >/dev/null 2>&1; then
        if ask_yes_no "Install Uncomplicated Firewall (ufw)? (4.1.1)"; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y ufw >/dev/null 2>&1
            log_success "Installed ufw."
        else
            log_info "Skipped ufw installation. Cannot proceed with firewall configuration."
            return 0
        fi
    fi

    # SSH Fail-Safe Protection
    if ask_yes_no "CRITICAL: Allow SSH (Port 22/tcp) through the firewall to prevent lockout?"; then
        ufw allow 22/tcp >/dev/null 2>&1
        log_success "Allowed SSH (Port 22/tcp)."
    else
        log_warn "Skipped allowing SSH. Proceed with caution if connected remotely."
    fi

    # Process the UFW_ALLOWLIST from the global config
    if [[ -n "${UFW_ALLOWLIST[*]}" ]]; then
        if ask_yes_no "Allow configured ports from UFW_ALLOWLIST (HTTP, HTTPS, NTP, DNS, etc.)?"; then
            for port in "${UFW_ALLOWLIST[@]}"; do
                # Skip any commented out or empty elements
                [[ -z "$port" || "$port" == \#* ]] && continue
                ufw allow "$port" >/dev/null 2>&1
                log_success "Allowed port/service: $port"
            done
        fi
    fi

    # 4.1.3 - 4.1.5 Configure default policies
    if ask_yes_no "Configure strict default UFW policies (Incoming: deny, Outgoing: allow, Routed: deny)?"; then
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1
        ufw default deny routed >/dev/null 2>&1
        log_success "Configured default UFW traffic policies."
    fi

    # 4.1.2 Ensure ufw service is configured and enabled
    if ask_yes_no "Enable and activate the UFW firewall? (4.1.2)"; then
        systemctl enable ufw.service >/dev/null 2>&1
        # Use --force to bypass the interactive prompt UFW gives when enabling via command line
        ufw --force enable >/dev/null 2>&1
        log_success "Enabled and activated UFW."
    fi

    log_success "Host based firewall configuration applied."
}

run_host_firewall() {
    log_info "Starting CIS Section 4.1: Configure Uncomplicated Firewall"
    manage_host_firewall
}

register_control "host_firewall" "run_host_firewall"
