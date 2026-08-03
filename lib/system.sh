#!/usr/bin/env bash

get_ubuntu_version() {
	source /etc/os-release
	echo "${VERSION_ID:-}"
}

is_ubuntu() {
	source /etc/os-release
	[[ "${ID:-}" == "ubuntu" ]]
}

get_hostname() {
	hostname
}

get_kernel() {
	uname -r
}

is_module_loaded() {
	local module="$1"
	lsmod | awk '{print $1}' | grep -qx "$module"
}

module_exists() {
	local module="$1"
	modinfo -n "$module" >/dev/null 2>&1
}

is_pkg_installed() {
	local pkg="$1"
	dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"
}

ask_yes_no() {
	while true; do
		read -r -p "$1 [y/n]: " response
		case "${response,,}" in
			y|yes) return 0 ;; # 0 means true/success in bash
            		n|no) return 1 ;;  # 1 means false/failure
            		*) echo "Please enter y or n." ;;
        	esac
    	done
}
