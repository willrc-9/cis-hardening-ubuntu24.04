#!/usr/bin/env bash

manage_network_modules() {
    local failed=0

    # Define the target network modules based on CIS 3.2.1 through 3.2.6[cite: 1]
    local modules=(
        "atm"  
        "can"  
        "dccp" 
        "rds"  
        "sctp" 
        "tipc" 
    )

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        for mod in "${modules[@]}"; do
            # 1. Check if the module is actively loaded into the running kernel
            if lsmod | grep -q "^${mod}\b"; then
                log_warn "Audit Failed (3.2.x): Network kernel module '$mod' is currently loaded."
                failed=1
            fi
            
            # 2. Check if the module is properly redirected to /bin/false or /bin/true[cite: 1]
            # Bypassing the modprobe binary and checking the text files directly using POSIX regex
            if ! grep -Eq "^[[:space:]]*install[[:space:]]+${mod}[[:space:]]+/bin/(false|true)([[:space:]]|$)" /etc/modprobe.d/*.conf 2>/dev/null; then
                log_warn "Audit Failed (3.2.x): Network kernel module '$mod' is not disabled (install /bin/false)."
                failed=1
            fi
            
            # 3. Check if the module is explicitly blacklisted[cite: 1]
            if ! grep -Eq "^[[:space:]]*blacklist[[:space:]]+${mod}([[:space:]]|$)" /etc/modprobe.d/*.conf 2>/dev/null; then
                log_warn "Audit Failed (3.2.x): Network kernel module '$mod' is not blacklisted."
                failed=1
            fi
        done

        if [[ $failed -eq 0 ]]; then
            log_success "Audit Passed: All prohibited network kernel modules are disabled."
        fi
        return $failed
    fi

    # --- APPLY MODE ---
    log_info "Applying control: Network Kernel Modules (CIS 3.2.x)"

    # Ensure the modprobe configuration directory exists
    mkdir -p /etc/modprobe.d

    for mod in "${modules[@]}"; do
        if ask_yes_no "Enforce disabling of the '$mod' network kernel module?"; then
            # Attempt to safely unload the module if it is currently running
            modprobe -r "$mod" >/dev/null 2>&1 || true
            rmmod "$mod" >/dev/null 2>&1 || true
            
            # Create the lockdown configuration file
            local conf_file="/etc/modprobe.d/60-${mod}.conf"
            echo "install $mod /bin/false" > "$conf_file"
            echo "blacklist $mod" >> "$conf_file"
            
            log_success "Disabled and blacklisted $mod kernel module."
        else
            log_info "Skipped disabling $mod."
        fi
    done

    log_success "Network kernel modules configuration applied."
}

run_network_modules() {
    log_info "Starting CIS Section 3.2: Configure Network Kernel Modules"
    manage_network_modules
}

register_control "network_modules" "run_network_modules"
