#!/usr/bin/env bash

# fs names
manage_filesystems2() {
local failed=0

# Filenames to block or audit
modname=(
	"cramfs"
	"freevxfs"
	"hfs"
	"hfsplus"
	"jffs2"
	"overlay"
	"squashfs"
	"udf"
)

if [[ "$MODE" == "audit" ]]; then
	for mod in "${modname[@]}"; do
		output=$(lsmod | grep $mod || true)
		if [[ -z "$output" ]]; then
			log_success "'$mod' is not configured"
		else
			failed=1
			log_warn "'$mod' is still configured"
		fi
	done
	return $failed
fi

#for loop to go through all fs
for mod in "${modname[@]}"; do
	#unload module
	modprobe -r $mod 2>/dev/null
	rmmod $mod 2>/dev/null
	
	#blacklist module
	touch /etc/modprobe.d/99-cis-$mod.conf
	printf '%s\n' "" "install $mod /bin/false" >> /etc/modprobe.d/99-cis-$mod.conf
done
}
run_filesystems2(){
	log_info "Running Filesystems (Updated) (CIS 1.1.1)"
	manage_filesystems2
	log_success "Filesystems (Updated) Completed."
}
register_control "filesystems2" "run_filesystems2"
