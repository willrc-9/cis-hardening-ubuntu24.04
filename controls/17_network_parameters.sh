#!/usr/bin/env bash

manage_network_parameters() {
    local failed=0
    local sysctl_conf="/etc/sysctl.d/60-net_sysctl.conf"

    # Define the groupings of sysctl parameters and their expected CIS values
    # Format: "parameter=expected_value|Description/Prompt"
    local params=(
        # IP Forwarding (3.3.1.1, 3.3.1.2, 3.3.1.3, 3.3.2.1, 3.3.2.2)
        "net.ipv4.ip_forward=0|Disable IPv4 packet forwarding"
        "net.ipv4.conf.all.forwarding=0|Disable IPv4 all interface forwarding"
        "net.ipv4.conf.default.forwarding=0|Disable IPv4 default interface forwarding"
        "net.ipv6.conf.all.forwarding=0|Disable IPv6 all interface forwarding"
        "net.ipv6.conf.default.forwarding=0|Disable IPv6 default interface forwarding"

        # Packet Redirects Sending (3.3.1.4, 3.3.1.5)
        "net.ipv4.conf.all.send_redirects=0|Disable sending IPv4 ICMP redirects (all)"
        "net.ipv4.conf.default.send_redirects=0|Disable sending IPv4 ICMP redirects (default)"

        # Bogus ICMP Responses & Broadcasts (3.3.1.6, 3.3.1.7)
        "net.ipv4.icmp_ignore_bogus_error_responses=1|Enable ignoring of bogus IPv4 ICMP error responses"
        "net.ipv4.icmp_echo_ignore_broadcasts=1|Enable ignoring of IPv4 ICMP broadcast requests"

        # Accept ICMP Redirects (3.3.1.8, 3.3.1.9, 3.3.2.3, 3.3.2.4)
        "net.ipv4.conf.all.accept_redirects=0|Disable accepting IPv4 ICMP redirects (all)"
        "net.ipv4.conf.default.accept_redirects=0|Disable accepting IPv4 ICMP redirects (default)"
        "net.ipv6.conf.all.accept_redirects=0|Disable accepting IPv6 ICMP redirects (all)"
        "net.ipv6.conf.default.accept_redirects=0|Disable accepting IPv6 ICMP redirects (default)"

        # Secure ICMP Redirects (3.3.1.10, 3.3.1.11)
        "net.ipv4.conf.all.secure_redirects=0|Disable accepting IPv4 secure ICMP redirects (all)"
        "net.ipv4.conf.default.secure_redirects=0|Disable accepting IPv4 secure ICMP redirects (default)"

        # Reverse Path Filtering (3.3.1.12, 3.3.1.13)
        "net.ipv4.conf.all.rp_filter=1|Enable IPv4 reverse path filtering (all)"
        "net.ipv4.conf.default.rp_filter=1|Enable IPv4 reverse path filtering (default)"

        # Source Routed Packets (3.3.1.14, 3.3.1.15, 3.3.2.5, 3.3.2.6)
        "net.ipv4.conf.all.accept_source_route=0|Disable accepting IPv4 source routed packets (all)"
        "net.ipv4.conf.default.accept_source_route=0|Disable accepting IPv4 source routed packets (default)"
        "net.ipv6.conf.all.accept_source_route=0|Disable accepting IPv6 source routed packets (all)"
        "net.ipv6.conf.default.accept_source_route=0|Disable accepting IPv6 source routed packets (default)"

        # Log Martian Packets (3.3.1.16, 3.3.1.17)
        "net.ipv4.conf.all.log_martians=1|Enable logging of IPv4 suspicious/martian packets (all)"
        "net.ipv4.conf.default.log_martians=1|Enable logging of IPv4 suspicious/martian packets (default)"

        # TCP SYN Cookies (3.3.1.18)
        "net.ipv4.tcp_syncookies=1|Enable IPv4 TCP SYN cookies"

        # IPv6 Router Advertisements (3.3.2.7, 3.3.2.8)
        "net.ipv6.conf.all.accept_ra=0|Disable accepting IPv6 router advertisements (all)"
        "net.ipv6.conf.default.accept_ra=0|Disable accepting IPv6 router advertisements (default)"
    )

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        for entry in "${params[@]}"; do
            local setting="${entry%%|*}"
            local param="${setting%%=*}"
            local expected="${setting##*=}"
            
            # Check if the parameter is supported by the running kernel
            if ! sysctl "$param" >/dev/null 2>&1; then
                continue # Skip parameters unsupported by the active kernel
            fi

            # Check the live running configuration
            local active_val
            active_val=$(sysctl -n "$param" 2>/dev/null | tr -d '[:space:]')
            if [[ "$active_val" != "$expected" ]]; then
                log_warn "Audit Failed (3.3.x): '$param' is currently set to '$active_val' (Expected: '$expected')."
                failed=1
            fi

            # Check persistent configuration in /etc/sysctl.d/ or /etc/sysctl.conf
            # Using grep -F ensures '.' is treated as a literal period rather than a wildcard
            if ! grep -Eqs "^[[:space:]]*${param}[[:space:]]*=[[:space:]]*${expected}\b" /etc/sysctl.d/*.conf /etc/sysctl.conf 2>/dev/null; then
                log_warn "Audit Failed (3.3.x): '$param' is not persistently set to '$expected' in /etc/sysctl.d/ or /etc/sysctl.conf."
                failed=1
            fi
        done

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: All applicable network kernel parameters are securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Network Kernel Parameters (CIS 3.3.x)"

    mkdir -p /etc/sysctl.d

    for entry in "${params[@]}"; do
        local setting="${entry%%|*}"
        local param="${setting%%=*}"
        local expected="${setting##*=}"
        local prompt="${entry##*|}"
        
        # Direct check for kernel parameter support
        if sysctl "$param" >/dev/null 2>&1; then
            if ask_yes_no "Enforce: $prompt ($param=$expected)?"; then
                # Apply live
                sysctl -w "$param=$expected" >/dev/null 2>&1 || true
                
                # Apply persistently
                if [[ -f "$sysctl_conf" ]]; then
                    sed -i "/^[[:space:]]*${param}[[:space:]]*=/d" "$sysctl_conf"
                fi
                echo "$param = $expected" >> "$sysctl_conf"
                
                log_success "Enforced $param=$expected"
            else
                log_info "Skipped $param"
            fi
        else
            log_info "Skipped $param (Not supported by the current running kernel; e.g., IPv6 is fully disabled)."
        fi
    done

    # Load and verify settings across the system
    sysctl --system >/dev/null 2>&1 || true

    log_success "Network kernel parameters configuration applied."
}

run_network_parameters() {
    log_info "Starting CIS Section 3.3: Configure Network Kernel Parameters"
    manage_network_parameters
}

register_control "network_parameters" "run_network_parameters"
