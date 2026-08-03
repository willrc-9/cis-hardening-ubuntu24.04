#!/usr/bin/env bash

manage_gdm() {
    local failed=0
    
    # QAC Banner formatted for dconf (requires single line with \n for breaks)
    local dconf_banner=" *** WARNING QUEEN ANNE'S COUNTY (QAC) IT SYSTEM ***\n You are accessing a system owned and operated by Queen Anne's County.\n Use of this system is restricted to authorized users only and by continuing to use this system,\n you agree to do so in accordance with the IT Acceptable Use Policy (700-001).\n Systems and networks are monitored for security purposes.\n Unauthorized use is strictly prohibited and may result in disciplinary action, civil liability, and/or criminal prosecution.\n If you are not authorized to access this system, disconnect immediately.\n For support, or to report missing equipment, please call 410-758-6607."

    # Configuration paths
    local gdm_profile="/etc/dconf/profile/gdm"
    local gdm_db_dir="/etc/dconf/db/gdm.d"
    local local_db_dir="/etc/dconf/db/local.d"
    local local_locks_dir="/etc/dconf/db/local.d/locks"
    local gdm_custom="/etc/gdm3/custom.conf"

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        # Check if the GDM package is actually installed
        if ! is_pkg_installed "gdm3"; then
            log_success "Audit Passed (1.7.x): GNOME Display Manager (GDM) is not installed. Controls are not applicable."
            return 0
        fi

        # 1.7.1 - 1.7.2: GDM Login Banner and User List
        if ! grep -q "banner-message-enable=true" "$gdm_db_dir/"* 2>/dev/null; then
            log_warn "Audit Failed (1.7.1): GDM login banner is not enabled."
            failed=1
        fi
        if ! grep -q "disable-user-list=true" "$gdm_db_dir/"* 2>/dev/null; then
            log_warn "Audit Failed (1.7.2): GDM disable-user-list is not configured."
            failed=1
        fi

        # 1.7.3 - 1.7.5: Screen lock, automount, and autorun-never
        if ! grep -q "lock-enabled=true" "$local_db_dir/"* 2>/dev/null; then
            log_warn "Audit Failed (1.7.3): GDM screen lock is not enabled."
            failed=1
        fi
        if ! grep -q "automount=false" "$local_db_dir/"* 2>/dev/null; then
            log_warn "Audit Failed (1.7.4): GDM automount is not disabled."
            failed=1
        fi
        if ! grep -q "autorun-never=true" "$local_db_dir/"* 2>/dev/null; then
            log_warn "Audit Failed (1.7.5): GDM autorun-never is not configured."
            failed=1
        fi

        # 1.7.6: Ensure XDMCP is not enabled
        if [[ -f "$gdm_custom" ]] && grep -Eqi '^\s*Enable\s*=\s*true' "$gdm_custom"; then
            log_warn "Audit Failed (1.7.6): XDMCP is enabled in $gdm_custom."
            failed=1
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: GDM is fully secured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: GNOME Display Manager"
    if ! is_pkg_installed "gdm3"; then
        log_success "GDM is not installed. Skipping."
        return 0
    fi

    mkdir -p "$gdm_db_dir" "$local_db_dir" "$local_locks_dir"
    
    local gdm_profile_content="user-db:user\nsystem-db:gdm\nfile-db:/usr/share/gdm/greeter-dconf-defaults\n"
    local login_content="[org/gnome/login-screen]\n"

    if ask_yes_no "Configure GDM banner message?"; then
        login_content+="banner-message-enable=true\nbanner-message-text='$dconf_banner'\n"
    fi
    if ask_yes_no "Configure GDM disable-user-list?"; then
        login_content+="disable-user-list=true\n"
    fi

    # Only write to the login db if we added settings to it
    if [[ "$login_content" != "[org/gnome/login-screen]\n" ]]; then
        echo -e "$gdm_profile_content" > "$gdm_profile"
        echo -e "$login_content" > "$gdm_db_dir/01-banner-and-login"
        log_success "Configured GDM login settings."
    fi

    local sec_screensaver="[org/gnome/desktop/screensaver]\n"
    local sec_media="[org/gnome/desktop/media-handling]\n"
    local lock_content=""

    if ask_yes_no "Configure GDM screen lock?"; then
        sec_screensaver+="lock-enabled=true\nidle-activation-enabled=true\n"
        lock_content+="/org/gnome/desktop/screensaver/lock-enabled\n/org/gnome/desktop/screensaver/idle-activation-enabled\n"
    fi
    if ask_yes_no "Configure GDM automount?"; then
        sec_media+="automount=false\nautomount-open=false\n"
        lock_content+="/org/gnome/desktop/media-handling/automount\n/org/gnome/desktop/media-handling/automount-open\n"
    fi
    if ask_yes_no "Configure GDM autorun-never?"; then
        sec_media+="autorun-never=true\n"
        lock_content+="/org/gnome/desktop/media-handling/autorun-never\n"
    fi

    if [[ -n "$lock_content" ]]; then
        echo -e "user-db:user\nsystem-db:local" > "/etc/dconf/profile/user"
        echo -e "${sec_screensaver}\n${sec_media}" > "$local_db_dir/00-security-settings"
        echo -e "$lock_content" > "$local_locks_dir/00-security-settings-lock"
        dconf update >/dev/null 2>&1 || log_warn "Failed to execute dconf update."
        log_success "Configured GDM session security settings."
    fi

    if ask_yes_no "Disable XDMCP?"; then
        if [[ -f "$gdm_custom" ]]; then
            if grep -qi '\[xdmcp\]' "$gdm_custom"; then
                sed -i '/\[xdmcp\]/a Enable=false' "$gdm_custom"
                sed -i '/^\s*Enable\s*=\s*true/d' "$gdm_custom"
            else
                echo -e "\n[xdmcp]\nEnable=false" >> "$gdm_custom"
            fi
            log_success "Disabled XDMCP."
        fi
    fi

    if ask_yes_no "Configure Xwayland (Enable Wayland)?"; then
        if [[ -f "$gdm_custom" ]]; then
            sed -i 's/^WaylandEnable=false/#WaylandEnable=false/g' "$gdm_custom"
            log_success "Ensured Wayland is enabled."
        fi
    fi
    }

run_gdm() {
    log_info "Starting CIS Section 1.7: Configure GNOME Display Manager"
    manage_gdm
}

register_control "gdm" "run_gdm"
