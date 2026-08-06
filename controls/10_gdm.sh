#!/usr/bin/env bash

manage_gdm() {
    local failed=0
    
    # Configuration paths
    local gdm_profile="/etc/dconf/profile/gdm"
    local gdm_db_dir="/etc/dconf/db/gdm.d"
    local local_db_dir="/etc/dconf/db/local.d"
    local local_locks_dir="/etc/dconf/db/local.d/locks"
    local gdm_custom="/etc/gdm3/custom.conf"

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        if ! is_pkg_installed "gdm3"; then
            log_success "Audit Passed (1.7.x): GNOME Display Manager (GDM) is not installed. Controls are not applicable."
            return 0
        fi

        if ! grep -q "banner-message-enable=true" "$gdm_db_dir/"* 2>/dev/null; then
            log_warn "Audit Failed (1.7.1): GDM login banner is not enabled."
            failed=1
        fi
        #                                                       # Put the first line of message here
        if ! grep -q "disable-user-list=true" "$gdm_db_dir/"* 2>/dev/nu ADD CUSTOM MESSAGE HERE; then
            log_warn "Audit Failed (1.7.2): GDM disable-user-list is not configured."
            failed=1
        fi
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
    
    # 1.7.1 & 1.7.2: Configure GDM Profile, Banner, and User List
    local gdm_profile_content="user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults"

    local login_content="[org/gnome/login-screen]"

    if ask_yes_no "Configure GDM banner message?"; then
        # We append using physical newlines in the script, but keep the literal \n and \' inside the banner string
        login_content="$login_content
banner-message-enable=true
banner-message-text=' ADD CUSTOM MESSAGE HERE \n You are accessing a system owned and operated by COMPANYNAME.\n Use of this system is restricted to authorized users only and by continuing to use this system,\n you agree to do so in accordance with the IT Acceptable Use Policy.\n Systems and networks are monitored for security purposes.\n Unauthorized use is strictly prohibited and may result in disciplinary action, civil liability, and/or criminal prosecution.\n If you are not authorized to access this system, disconnect immediately.\n For support, or to report missing equipment, please call PHONE NUMBER.'"
    fi
    
    if ask_yes_no "Configure GDM disable-user-list?"; then
        login_content="$login_content
disable-user-list=true"
    fi

    # Only write to the login db if we added settings to it
    if [[ "$login_content" != "[org/gnome/login-screen]" ]]; then
        echo "$gdm_profile_content" > "$gdm_profile"
        echo "$login_content" > "$gdm_db_dir/01-banner-and-login"
        log_success "Configured GDM login settings."
    fi

    # 1.7.3 - 1.7.5: Session Security Settings
    local sec_settings=""
    local lock_content=""

    if ask_yes_no "Configure GDM screen lock?"; then
        sec_settings="$sec_settings
[org/gnome/desktop/screensaver]
lock-enabled=true
idle-activation-enabled=true"
        lock_content="$lock_content
/org/gnome/desktop/screensaver/lock-enabled
/org/gnome/desktop/screensaver/idle-activation-enabled"
    fi
    
    if ask_yes_no "Configure GDM automount?"; then
        sec_settings="$sec_settings
[org/gnome/desktop/media-handling]
automount=false
automount-open=false"
        lock_content="$lock_content
/org/gnome/desktop/media-handling/automount
/org/gnome/desktop/media-handling/automount-open"
    fi
    
    if ask_yes_no "Configure GDM autorun-never?"; then
        # Ensure media handling section exists if automount wasn't selected
        if [[ "$sec_settings" != *"[org/gnome/desktop/media-handling]"* ]]; then
            sec_settings="$sec_settings
[org/gnome/desktop/media-handling]"
        fi
        sec_settings="$sec_settings
autorun-never=true"
        lock_content="$lock_content
/org/gnome/desktop/media-handling/autorun-never"
    fi

    if [[ -n "$sec_settings" ]]; then
        echo "user-db:user
system-db:local" > "/etc/dconf/profile/user"
        
        # We use standard echo here so it writes exactly what is in the variables
        echo "$sec_settings" > "$local_db_dir/00-security-settings"
        
        # Remove any leading blank line from lock_content before writing
        echo "${lock_content#$'\n'}" > "$local_locks_dir/00-security-settings-lock"
        
        # Execute update and log result
        if dconf update >/dev/null 2>&1; then
            log_success "Configured GDM session security settings and successfully compiled dconf database."
        else
            log_warn "Failed to execute dconf update."
        fi
    fi

    # 1.7.6 & 1.7.7: XDMCP and Xwayland
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
