#!/usr/bin/env bash

manage_apt_dependencies() {
    local apt_conf="/etc/apt/apt.conf.d/60-cis-hardening"
    local failed=0

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # Capture output first to avoid SIGPIPE crashes if 'set -o pipefail' is enabled
        local apt_dump
        apt_dump=$(apt-config dump 2>/dev/null)

        # 1.2.1.2 Ensure package manager weak dependencies are disabled
        # Using standard >/dev/null instead of -q to ensure the pipeline finishes cleanly
        if ! echo "$apt_dump" | grep -iE 'APT::Install-Recommends.*(false|0)' > /dev/null; then
            log_warn "Audit Failed (1.2.1.2): APT::Install-Recommends is not disabled."
            failed=1
        fi
        
        if ! echo "$apt_dump" | grep -iE 'APT::Install-Suggests.*(false|0)' > /dev/null; then
            log_warn "Audit Failed (1.2.1.2): APT::Install-Suggests is not disabled."
            failed=1
        fi
        
        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: Weak dependencies are disabled."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Disable APT Weak Dependencies (CIS 1.2.1.2)"
    if ask_yes_no "Disable APT Install-Recommends and Install-Suggests? (1.2.1.2)"; then
        echo 'APT::Install-Recommends "0";' > "$apt_conf"
        echo 'APT::Install-Suggests "0";' >> "$apt_conf"
        chmod 644 "$apt_conf"
        log_success "Disabled weak dependencies in $apt_conf."
    fi
}

run_apt_config() {
    log_info "Starting CIS Section 1.2: Package Management"
    manage_apt_dependencies
}

register_control "package_manager" "run_apt_config"
