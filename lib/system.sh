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
