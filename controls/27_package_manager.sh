#!/usr/bin/env bash

manage_apt_dependencies() {
    local apt_conf="/etc/apt/apt.conf.d/60-cis-hardening"

    if [[ "$MODE" == "audit" ]]; then
        if ! apt-config dump | grep -q 'APT::Install-Recommends "false"'; then
            log_warn "Audit Failed: APT::Install-Recommends is not false."
            return 1
        fi
        if ! apt-config dump | grep -q 'APT::Install-Suggests "false"'; then
            log_warn "Audit Failed: APT::Install-Suggests is not false."
            return 1
        fi
        log_success "Audit Passed: Weak dependencies are disabled."
        return 0
    fi

    log_info "Applying control: Disable APT Weak Dependencies"
    if ask_yes_no "Disable APT Install-Recommends and Install-Suggests?"; then
        echo 'APT::Install-Recommends "false";' > "$apt_conf"
        echo 'APT::Install-Suggests "false";' >> "$apt_conf"
        log_success "Disabled weak dependencies in $apt_conf."
    fi
}

register_control "apt_config" "manage_apt_dependencies"
