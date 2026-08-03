#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nullglob

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Defaults
MODE="${DEFAULT_MODE:-audit}"
ACTION="all"
TARGET_SECTION=""

# Load libraries
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/files.sh"
source "$SCRIPT_DIR/lib/system.sh"
source "$SCRIPT_DIR/lib/validation.sh"
source "$SCRIPT_DIR/lib/control_runner.sh"

# Load config if present
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
	source "$SCRIPT_DIR/config.conf"
fi

# Load controls
load_controls() {
	local control_file

	for control_file in "$SCRIPT_DIR"/controls/*.sh; do
		source "$control_file"
	done
}

usage() {
	cat <<EOF
Usage:
	$0 --list
	$0 --audit [--all | --include <section> | --exclude <section>]
	$0 --apply [--all | --include <section> | --exclude <section>]


Defaults:
	no arguments -> --audit --all
EOF
}


parse_args() {
	if [[ $# -eq 0 ]]; then
		MODE="audit"
		ACTION="all"
		return 0
	fi

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--audit)
				MODE="audit"
				;;
			--apply)
				MODE="apply"
				;;
			--all)
				ACTION="all"
				;;
			--include)
				ACTION="include"
				TARGET_SECTION="${2:-}"
				if [[ -z "$TARGET_SECTION" ]]; then
					echo "Missing section name for --exclude" >&2
					usage
					exit 1
				fi
				shift
				;;
			--exclude)
				ACTION="exclude"
				TARGET_SECTION="${2:-}"
				if [[ -z "$TARGET_SECTION" ]]; then
					echo "Missing section name for --exclude" >&2
					usage
					exit 1
				fi
        			shift
				;;
			--list)
				ACTION="list"
				;;
			-h|--help)
				usage
				exit 0
				;;
			*)
				echo "Unknown argument: $1" >&2
				usage
				exit 1
				;;
		esac
		shift
	done
}


main() {
	require_root
	init_logging

	require_commands bash cp grep lsmod modprobe tee mkdir touch hostname uname

	load_controls
	parse_args "$@"

	log_info "Host: $(get_hostname)"
	log_info "Ubuntu version: $(get_ubuntu_version)"
	log_info "Mode: $MODE"

	case "$ACTION" in
		list)
			list_sections
			;;
		include)
			run_section "$TARGET_SECTION"
			;;
		exclude)
			run_all_sections_except "$TARGET_SECTION"
			;;
		all)
			run_all_sections
			;;
		*)
			usage
			exit 1
			;;
	esac
}

main "$@"
