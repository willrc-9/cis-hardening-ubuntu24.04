#!/usr/bin/env bash

manage_file_permissions() {
    local failed=0

    # Define the target files and their expected permissions/ownership
    # Format: "file|expected_perms|expected_owner|expected_group"
    local sys_files=(
        "/etc/passwd|644|root|root"
        "/etc/shadow|640|root|shadow"
        "/etc/group|644|root|root"
        "/etc/gshadow|640|root|shadow"
        "/etc/passwd-|644|root|root"
        "/etc/shadow-|640|root|shadow"
        "/etc/group-|644|root|root"
        "/etc/gshadow-|640|root|shadow"
    )

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        
        # 6.3.x Ensure permissions and ownership on system files are configured
        for entry in "${sys_files[@]}"; do
            local file="${entry%%|*}"
            local expected_perms
            expected_perms=$(echo "$entry" | cut -d'|' -f2)
            local expected_owner
            expected_owner=$(echo "$entry" | cut -d'|' -f3)
            local expected_group
            expected_group=$(echo "$entry" | cut -d'|' -f4)

            if [[ -f "$file" ]]; then
                local current_perms
                current_perms=$(stat -c "%a" "$file")
                local current_owner
                current_owner=$(stat -c "%U" "$file")
                local current_group
                current_group=$(stat -c "%G" "$file")

                # Shadow files are sometimes strictly 000, which is also acceptable
                if [[ "$file" == *shadow* && "$current_perms" == "000" ]]; then
                    expected_perms="000"
                fi
                # Backup files are sometimes strictly 600 root:root, which is also acceptable
                if [[ "$file" == *- && "$current_perms" == "600" && "$current_owner" == "root" && "$current_group" == "root" ]]; then
                    expected_perms="600"
                    expected_owner="root"
                    expected_group="root"
                fi

                if [[ "$current_perms" != "$expected_perms" || "$current_owner" != "$expected_owner" || "$current_group" != "$expected_group" ]]; then
                    log_warn "Audit Failed (6.3.x): $file is $current_perms $current_owner:$current_group (Expected: $expected_perms $expected_owner:$expected_group)."
                    failed=1
                fi
            else
                log_info "Audit (6.3.x): $file does not exist, skipping."
            fi
        done

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: System file permissions and ownership are securely configured."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: System File Permissions (CIS 6.3.x)"

    if ask_yes_no "Enforce strict permissions and ownership on core system files (/etc/passwd, /etc/shadow, etc.)? (6.3.x)"; then
        for entry in "${sys_files[@]}"; do
            local file="${entry%%|*}"
            local expected_perms
            expected_perms=$(echo "$entry" | cut -d'|' -f2)
            local expected_owner
            expected_owner=$(echo "$entry" | cut -d'|' -f3)
            local expected_group
            expected_group=$(echo "$entry" | cut -d'|' -f4)

            if [[ -f "$file" ]]; then
                chown "$expected_owner:$expected_group" "$file" >/dev/null 2>&1
                chmod "$expected_perms" "$file" >/dev/null 2>&1
                log_success "Secured $file ($expected_perms $expected_owner:$expected_group)."
            fi
        done
    fi

    log_info "Note: CIS 6.3 also recommends auditing the entire filesystem for unowned or world-writable files."
    log_info "Because this scan can take heavily impact disk I/O, it is omitted from the automated apply phase."
    log_info "You can manually scan for them using:"
    log_info "  find / -xdev -nouser -o -nogroup"
    log_info "  find / -xdev -type f -perm -0002"

    log_success "System file permissions configuration applied."
}

run_file_permissions() {
    log_info "Starting CIS Section 6.3: System File Permissions"
    manage_file_permissions
}

register_control "file_permissions" "run_file_permissions"
