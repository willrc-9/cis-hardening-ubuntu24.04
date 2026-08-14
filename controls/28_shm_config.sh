#!/usr/bin/env bash

options=("nodev" "nosuid" "noexec")

manage_shm(){
	local failed=0
	#proper fstab entry
	local output="/dev/shm   tmpfs  tmpfs  rw,nosuid,nodev,noexec,relatime,seclabel"
	local output2=""
	#audit
	if [[ "$MODE" == "audit" ]]; then
		output2=$(findmnt -kn /dev/shm)
		for opt in "${options[@]}"; do
			if [[ "$output2" == *"$opt"* ]]; then
				log_success "Audit Passed - /dev/shm contains the '$opt' flag in /etc/fstab (1.1.2.2.X)"
			else
				failed=1
				log_warn "Audit Failed - /dev/shm does not contain the '$opt' flag in /etc/fstab (1.1.2.2.X)"
			fi
		done
		return $failed
	fi

	# apply

	echo "tmpfs	/dev/shm	tmpfs     defaults,rw,nosuid,nodev,noexec,relatime,size=2G  0 0" >> /etc/fstab
		mount -o remount /dev/shm
		systemctl daemon-reload
}

run_shmconfig() {
	log_info "Starting CIS Section 1.1.2.2: Configure /dev/shm (shared memory)"
	manage_shm
	log_success "Shared Memory section completed (CIS 1.1.2.2)"
}
register_control "shm" "run_shmconfig"
