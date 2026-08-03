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
    log_info "Applying control: Configure GNOME Display Manager (CIS 1.7.x)"

    if ! is_pkg_installed "gdm3"; then
        log_success "GNOME Display Manager (GDM) is not installed. Skipping GDM configurations."
        return 0
    fi

    # Ensure required dconf directories exist
    mkdir -p "$gdm_db_dir"
    mkdir -p "$local_db_dir"
    mkdir -p "$local_locks_dir"

    # 1.7.1 & 1.7.2: Configure GDM Profile, Banner, and User List
    echo -e "user-db:user\nsystem-db:gdm\nfile-db:/usr/share/gdm/greeter-dconf-defaults" > "$gdm_profile"
    
    cat <<EOF > "$gdm_db_dir/01-banner-and-login"
[org/gnome/login-screen]
banner-message-enable=true
banner-message-text='$dconf_banner'
disable-user-list=true
EOF

    # 1.7.3 - 1.7.5: Configure Screen lock, automount, and autorun
    # Create the user profile to look at the local dconf database
    echo -e "user-db:user\nsystem-db:local" > "/etc/dconf/profile/user"

    cat <<EOF > "$local_db_dir/00-security-settings"
[org/gnome/desktop/screensaver]
lock-enabled=true
idle-activation-enabled=true

[org/gnome/desktop/media-handling]
automount=false
automount-open=false
autorun-never=true
EOF

    # Lock the settings so standard users cannot override them
    cat <<EOF > "$local_locks_dir/00-security-settings-lock"
/org/gnome/desktop/screensaver/lock-enabled
/org/gnome/desktop/screensaver/idle-activation-enabled
/org/gnome/desktop/media-handling/automount
/org/gnome/desktop/media-handling/automount-open
/org/gnome/desktop/media-handling/autorun-never
EOF

    # Update the dconf databases to apply the files we just created
    dconf update >/dev/null 2>&1 || log_warn "Failed to execute 'dconf update'. Is dconf-cli installed?"

    # 1.7.6 & 1.7.7: Disable XDMCP and configure Xwayland
    if [[ -f "$gdm_custom" ]]; then
        backup_file "$gdm_custom"
        # Disable XDMCP by explicitly setting Enable=false under the [xdmcp] section
        if grep -qi '\[xdmcp\]' "$gdm_custom"; then
            sed -i '/\[xdmcp\]/a Enable=false' "$gdm_custom"
            sed -i '/^\s*Enable\s*=\s*true/d' "$gdm_custom"
        else
            echo -e "\n[xdmcp]\nEnable=false" >> "$gdm_custom"
        fi
        
        # Ensure Wayland is not disabled (which forces insecure X11/Xwayland)
        sed -i 's/^WaylandEnable=false/#WaylandEnable=false/g' "$gdm_custom"
    fi

    log_success "Applied (1.7.1 - 1.7.7): GDM parameters and graphical restrictions enforced."
}

run_gdm() {
    log_info "Starting CIS Section 1.7: Configure GNOME Display Manager"
    manage_gdm
}

register_control "gdm" "run_gdm"
