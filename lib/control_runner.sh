#!/usr/bin/env bash

declare -ag CONTROL_ORDER=()
declare -A CONTROLS=()

register_section() {
	local name="$1"
	local function="$2"

	if [[ -z "${CONTROLS[$name]:-}" ]]; then
		CONTROL_ORDER+=("$name")
	fi

	CONTROLS["$name"]="$function"
}

register_control() {
	register_section "$@"
}

run_section() {
	local name="$1"

	if [[ -z "${CONTROLS[$name]:-}" ]]; then
		log_error "Unknown control section: $name"
		return 1
	fi

	log_info "Running control section: $name"
	"${CONTROLS[$name]}"
}

run_all_sections() {
	local rc=0
	local section

	for section in "${CONTROL_ORDER[@]}"; do
		if ! run_section "$section"; then
			rc=1
		fi
	done

	return "$rc"
}

run_all_sections_except() {
	local excluded="$1"
	local rc=0
	local section

	for section in "${CONTROLS_ORDER[@]}"; do
		if [[ "$section" == "$excluded" ]]; then
			log_warn "Skipping excluded control section: $section"
			continue
		fi

		if ! run_section "$section"; then
			rc=1
		fi
	done

	return "$rc"
}

list_sections() {
	echo "Available control sections:"
	local section
	for section in "${CONTROL_ORDER[@]}"; do
		echo " - $section"
	done
}
