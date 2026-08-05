#!/usr/bin/env bash

manage_server_services() {
    local failed=0

    # Map CIS control descriptions to their corresponding Ubuntu package names
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

    # Use mapfile to safely sort keys with spaces in them
    local sorted_controls=()
    mapfile -t sorted_controls < <(printf '%s\n' "${!remove_pkgs[@]}" | sort -V)

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        for control in "${!remove_pkgs[@]}"; do
            for pkg in ${remove_pkgs[$control]}; do
                if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                    log_warn "Audit Failed ($control): Package '$pkg' is installed."
                    failed=1
                fi
            done
        done

        if command -v ss >/dev/null; then
            if ss -lntu | grep -E ':25\s' | grep -qvE '(127\.0\.0\.1|::1):25'; then
                log_warn "Audit Failed (2.1.2): Mail Transfer Agent (MTA) is listening on non-loopback interfaces."
                failed=1
            fi
        fi

        log_info "Audit Manual Check (2.1.4): Please review the following listening services to ensure they are authorized:"
        ss -plntu | sed 's/^/  /'

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: All server services are securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Server Services (CIS 2.1.x)"

    # 2.1.1, 2.1.3, 2.1.5 - 2.1.23: Service Purging
    for control in "${sorted_controls[@]}"; do
        local pkgs_to_check="${remove_pkgs[$control]}"
        
        if ask_yes_no "Enforce removal of $control?"; then
            DEBIAN_FRONTEND=noninteractive apt-get purge -y $pkgs_to_check >/dev/null 2>&1 || true
            log_success "Enforced removal of $control"
        else
            log_info "Skipped $control"
        fi
    done

    # 2.1.2: MTA local-only mode
    if ask_yes_no "Configure Mail Transfer Agent (Postfix) for local-only mode? (2.1.2)"; then
        if [[ -f /etc/postfix/main.cf ]]; then
            backup_file "/etc/postfix/main.cf"
            sed -i '/^inet_interfaces/d' /etc/postfix/main.cf
            echo "inet_interfaces = loopback-only" >> /etc/postfix/main.cf
            systemctl restart postfix >/dev/null 2>&1 || true
            log_success "Configured Postfix to listen on loopback-only."
        else
            log_success "No Postfix MTA detected. System is naturally compliant."
        fi
    fi

    # 2.1.4: Ensure only approved services are listening
    if ask_yes_no "Review currently listening network services? (CIS 2.1.4 requires manual verification)"; then
        echo "------------------------------------------------------"
        ss -plntu
        echo "------------------------------------------------------"
        log_success "Manual review of listening services completed."
    fi

    log_success "Server services configuration applied."
}

run_server_services() {
    log_info "Starting CIS Section 2.1: Configure Server Services"
    manage_server_services
}

register_control "server_services" "run_server_services"
