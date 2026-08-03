#!/usr/bin/env bash

manage_server_services() {
    local failed=0

    # Map CIS control descriptions to their corresponding Ubuntu package names
    # Note: Some controls list multiple possible packages to check
    declare -A remove_pkgs=(
        ["2.1.1 autofs"]="autofs"
        ["2.1.3 avahi daemon"]="avahi-daemon"
        ["2.1.5 dhcp server"]="isc-dhcp-server"
        ["2.1.6 web server"]="apache2 nginx lighttpd"
        ["2.1.7 dns server"]="bind9"
        ["2.1.8 ftp server"]="vsftpd proftpd-core pure-ftpd"
        ["2.1.9 dnsmasq"]="dnsmasq"
        ["2.1.10 ldap server"]="slapd"
        ["2.1.11 message access server"]="dovecot-core dovecot-imapd dovecot-pop3d cyrus-imapd cyrus-pop3d"
        ["2.1.12 nfs server"]="nfs-kernel-server"
        ["2.1.13 nis server"]="nis"
        ["2.1.14 print server"]="cups"
        ["2.1.15 rpcbind"]="rpcbind"
        ["2.1.16 rsync"]="rsync"
        ["2.1.17 samba file server"]="samba"
        ["2.1.18 snmp server"]="snmpd"
        ["2.1.19 telnet server"]="telnetd"
        ["2.1.20 tftp server"]="tftpd-hpa tftpd"
        ["2.1.21 web proxy server"]="squid"
        ["2.1.22 xinetd"]="xinetd"
        ["2.1.23 X window server"]="xserver-xorg*"
    )

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # Check all forbidden packages
        for control in "${!remove_pkgs[@]}"; do
            for pkg in ${remove_pkgs[$control]}; do
                # dpkg -l handles both exact names and wildcards (like xserver-xorg*)
                if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                    log_warn "Audit Failed ($control): Package '$pkg' is installed."
                    failed=1
                fi
            done
        done

        # 2.1.2: Ensure MTA is configured for local-only mode
        if command -v ss >/dev/null; then
            # Look for anything listening on port 25 that is NOT the local loopback (127.0.0.1 or ::1)
            if ss -lntu | grep -E ':25\s' | grep -qvE '(127\.0\.0\.1|::1):25'; then
                log_warn "Audit Failed (2.1.2): Mail Transfer Agent (MTA) is listening on non-loopback interfaces."
                failed=1
            fi
        fi

        # 2.1.4: Ensure only approved services are listening
        log_info "Audit Manual Check (2.1.4): Please review the following listening services to ensure they are authorized:"
        ss -plntu | sed 's/^/  /'

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: All server services are securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Server Services (CIS 2.1.x)"

    # Loop through and offer to purge each installed service category
    for control in "${!remove_pkgs[@]}"; do
        local pkgs_to_check="${remove_pkgs[$control]}"
        local found_pkgs=""

        # Detect if any of the target packages are currently installed
        for pkg in $pkgs_to_check; do
            if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                found_pkgs="$found_pkgs $pkg"
            fi
        done

        # Only trigger the interactive prompt if a forbidden package was found
        if [[ -n "$found_pkgs" ]]; then
            if ask_yes_no "Remove $control (Found:$found_pkgs)?"; then
                DEBIAN_FRONTEND=noninteractive apt-get purge -y $found_pkgs >/dev/null 2>&1
                log_success "Purged:$found_pkgs"
            else
                log_info "Skipped removing:$found_pkgs"
            fi
        fi
    done

    # 2.1.2: MTA local-only mode
    # Postfix is the default MTA on Ubuntu. If installed, bind it strictly to the loopback address.
    if [[ -f /etc/postfix/main.cf ]]; then
        if ask_yes_no "Configure Mail Transfer Agent (Postfix) for local-only mode? (2.1.2)"; then
            backup_file "/etc/postfix/main.cf"
            
            # Remove any existing inet_interfaces lines, then append the secure one
            sed -i '/^inet_interfaces/d' /etc/postfix/main.cf
            echo "inet_interfaces = loopback-only" >> /etc/postfix/main.cf
            
            systemctl restart postfix >/dev/null 2>&1 || true
            log_success "Configured Postfix to listen on loopback-only."
        fi
    fi

    log_success "Server services configuration applied."
}

run_server_services() {
    log_info "Starting CIS Section 2.1: Configure Server Services"
    manage_server_services
}

register_control "server_services" "run_server_services"
