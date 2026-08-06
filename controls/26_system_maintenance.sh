#!/usr/bin/env bash

manage_system_maintenance() {
    local failed=0

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 7.1.1 Ensure passwords are not empty
        local empty_pw
        empty_pw=$(awk -F: '($2 == "" ) { print $1 }' /etc/shadow)
        if [[ -n "$empty_pw" ]]; then
            log_warn "Audit Failed (7.1.1): Accounts found with empty passwords: $empty_pw"
            failed=1
        fi

        # 7.2.1 Ensure no duplicate UIDs exist
        local dup_uids
        dup_uids=$(awk -F: '{print $3}' /etc/passwd | sort -n | uniq -c | awk '$1 > 1 {print $2}')
        if [[ -n "$dup_uids" ]]; then
            log_warn "Audit Failed (7.2.1): Duplicate UIDs exist: $(echo "$dup_uids" | tr '\n' ' ')"
            failed=1
        fi

        # 7.2.2 Ensure no duplicate GIDs exist
        local dup_gids
        dup_gids=$(awk -F: '{print $3}' /etc/group | sort -n | uniq -c | awk '$1 > 1 {print $2}')
        if [[ -n "$dup_gids" ]]; then
            log_warn "Audit Failed (7.2.2): Duplicate GIDs exist: $(echo "$dup_gids" | tr '\n' ' ')"
            failed=1
        fi

        # 7.2.3 Ensure no duplicate user names exist
        local dup_users
        dup_users=$(awk -F: '{print $1}' /etc/passwd | sort | uniq -c | awk '$1 > 1 {print $2}')
        if [[ -n "$dup_users" ]]; then
            log_warn "Audit Failed (7.2.3): Duplicate usernames exist: $(echo "$dup_users" | tr '\n' ' ')"
            failed=1
        fi

        # 7.2.4 Ensure no duplicate group names exist
        local dup_groups
        dup_groups=$(awk -F: '{print $1}' /etc/group | sort | uniq -c | awk '$1 > 1 {print $2}')
        if [[ -n "$dup_groups" ]]; then
            log_warn "Audit Failed (7.2.4): Duplicate group names exist: $(echo "$dup_groups" | tr '\n' ' ')"
            failed=1
        fi

        # Audit interactive users' home directories, dotfiles, and legacy config files
        local users_failed=0
        for user_info in $(awk -F: '($3 >= 1000 && $1 != "nobody") {print $1":"$6}' /etc/passwd); do
            local user="${user_info%%:*}"
            local dir="${user_info##*:}"

            if [[ ! -d "$dir" ]]; then
                log_warn "Audit Failed (7.x): Home directory for $user ($dir) does not exist."
                users_failed=1
                continue
            fi

            # Check directory ownership
            local dir_owner
            dir_owner=$(stat -c "%U" "$dir")
            if [[ "$dir_owner" != "$user" ]]; then
                log_warn "Audit Failed (7.x): Home directory for $user is owned by $dir_owner."
                users_failed=1
            fi

            # Check directory permissions (750 or more restrictive)
            local dir_perms
            dir_perms=$(stat -c "%a" "$dir")
            if [[ "$dir_perms" =~ [^0-7] || "$dir_perms" > 750 ]]; then
                log_warn "Audit Failed (7.x): Home directory for $user has loose permissions ($dir_perms)."
                users_failed=1
            fi

            # Check for legacy files (.forward, .netrc, .rhosts)
            for file in .forward .netrc .rhosts; do
                if [[ -f "$dir/$file" ]]; then
                    log_warn "Audit Failed (7.x): User $user has a prohibited $file file."
                    users_failed=1
                fi
            done
        done

        if [[ $users_failed -eq 1 ]]; then
            failed=1
        fi

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: System Maintenance and Local User settings are secure."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: System Maintenance (CIS 7.x)"

    # Report un-fixable structural issues for manual review
    local empty_pw
    empty_pw=$(awk -F: '($2 == "" ) { print $1 }' /etc/shadow)
    if [[ -n "$empty_pw" ]]; then
        log_warn "MANUAL ACTION REQUIRED: The following accounts have empty passwords: $empty_pw"
    fi
    
    local dup_uids
    dup_uids=$(awk -F: '{print $3}' /etc/passwd | sort -n | uniq -c | awk '$1 > 1 {print $2}')
    if [[ -n "$dup_uids" ]]; then
        log_warn "MANUAL ACTION REQUIRED: Duplicate UIDs detected. Review /etc/passwd: $(echo "$dup_uids" | tr '\n' ' ')"
    fi

    if ask_yes_no "Enforce strict permissions and ownership on interactive user home directories (750)?"; then
        for user_info in $(awk -F: '($3 >= 1000 && $1 != "nobody") {print $1":"$6}' /etc/passwd); do
            local user="${user_info%%:*}"
            local dir="${user_info##*:}"

            if [[ -d "$dir" ]]; then
                # Fix ownership
                chown "$user" "$dir" >/dev/null 2>&1
                
                # Fix permissions on the home directory itself
                chmod 750 "$dir" >/dev/null 2>&1

                # Restrict permissions on all dotfiles inside the directory to prevent group/world write
                find "$dir" -maxdepth 1 -type f -name ".*" -exec chmod go-w {} \; >/dev/null 2>&1
            fi
        done
        log_success "Secured interactive user home directories and dotfiles."
    fi

    if ask_yes_no "Remove prohibited legacy configuration files (.forward, .netrc, .rhosts) from all home directories?"; then
        for user_info in $(awk -F: '($3 >= 1000 && $1 != "nobody") {print $6}' /etc/passwd); do
            local dir="$user_info"
            if [[ -d "$dir" ]]; then
                rm -f "$dir/.forward" "$dir/.netrc" "$dir/.rhosts" >/dev/null 2>&1
            fi
        done
        log_success "Removed prohibited legacy configuration files."
    fi

    log_success "System Maintenance configuration applied."
}

run_system_maintenance() {
    log_info "Starting CIS Section 7: System Maintenance"
    manage_system_maintenance
}

register_control "system_maintenance" "run_system_maintenance"
