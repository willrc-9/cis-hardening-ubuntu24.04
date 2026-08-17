#!/usr/bin/env bash

manage_partitions() {
    local failed=0
    local part="$1"
    local cmdout=""
    local options=("nodev" "nosuid")

    shift
    local options=("$@")

    # --- AUDIT MODE ---
    if [[ "$MODE" == "audit" ]]; then
        # Check if /home is an active mount point
        cmdout=$(findmnt -kn "$part" || true)
        
        if [[ -z "$cmdout" ]]; then
            log_warn "Audit Failed - no separate $part partition mounted (1.1.2.X)"
            failed=1
        else
            log_success "Audit Passed - separate $part partition mounted (1.1.2.X)"
            
            # Check the specific security flags
            for opt in "${options[@]}"; do
                if [[ "$cmdout" == *"$opt"* ]]; then
                    log_success "Audit Passed - $part contains the '$opt' flag (1.1.2.X)"
                else
                    log_warn "Audit Failed - $part does not contain the '$opt' flag (1.1.2.X)"
                    failed=1
                fi
            done
        fi
        return $failed
    fi
    
    # --- APPLY MODE ---
    # Note: A script cannot safely guess how to partition a disk. 
    # If a separate /home doesn't exist, we must prompt the admin to build one manually.
    if ! mountpoint -q /home; then
        log_warn "Manual Action Required: Cannot automatically build a separate $part partition."
        return 1
    fi

    log_info "Attempting to apply flags (${options[*]}) to existing $part partition..."
    
    # Safely inject the flags into the existing fstab entry using sed
    if grep -q "[[:space:]]${part}[[:space:]]" /etc/fstab; then
        # Backup fstab before editing
        cp -n /etc/fstab /etc/fstab.bak
        
	for opt in "${options[@]}"; do
        # Add options if missing
        	if ! grep -q "[[:space:]]${part}[[:space:]].*$opt" /etc/fstab; then
            		sed -i "s|\([[:space:]]${part}[[:space:]]\+[^[:space:]]\+\)|\1${opt},|" /etc/fstab
        	fi
	done
        
        log_success "$part partition updated in /etc/fstab"
        
        systemctl daemon-reload
        mount -o remount "$part"
    else
        log_warn "$part partition exists but is not managed in /etc/fstab."
    fi
}

run_partitionconfig() {
    local overall_failed=0

    log_info "Starting CIS 1.1.2.3: Configure /home partition"
    manage_partitions "/home" "nodev" "nosuid" || overall_failed=1

    log_info "Starting CIS 1.1.2.4 /var partition"
    manage_partitions "/var" "nodev" "nosuid" || overall_failed=1

    log_info "Starting CIS configuration: /var/log partition"
    manage_partitions "/var/log" "noexec" "nosuid" "nodev" || overall_failed=1

    log_info "Starting CIS configuration: /var/tmp partition"
    manage_partitions "/var/tmp" "noexec" "nosuid" "nodev" || overall_failed=1

    log_info "Starting CIS configuration: /var/log/audit partition"
    manage_partitions "/var/log/audit" "nodev" "noexec" "nosuid" || overall_failed=1

    return overall_failed

}
register_control "partitions" "run_partitionconfig"
