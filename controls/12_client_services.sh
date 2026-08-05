#!/usr/bin/env bash

manage_client_services() {
    local failed=0

    # Map CIS control descriptions to their corresponding Ubuntu package names
    declare -A remove_pkgs=(
        ["2.2.1 nis client"]="nis"
        ["2.2.2 rsh client"]="rsh-client rsh-redone-client"
        ["2.2.3 talk client"]="talk"
        ["2.2.4 telnet client"]="telnet"
        ["2.2.5 ldap client"]="ldap-utils"
        ["2.2.6 ftp client"]="ftp"
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

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: All prohibited client services are uninstalled."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Client Services (CIS 2.2.x)"

    for control in "${sorted_controls[@]}"; do
        local pkgs_to_check="${remove_pkgs[$control]}"
        
        if ask_yes_no "Enforce removal of $control?"; then
            DEBIAN_FRONTEND=noninteractive apt-get purge -y $pkgs_to_check >/dev/null 2>&1 || true
            log_success "Enforced removal of $control"
        else
            log_info "Skipped $control"
        fi
    done

    log_success "Client services configuration applied."
}

run_client_services() {
    log_info "Starting CIS Section 2.2: Configure Client Services"
    manage_client_services
}

register_control "client_services" "run_client_services"
