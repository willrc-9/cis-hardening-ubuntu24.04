#!/usr/bin/env bash

BACKUP_DIR="${BACKUP_DIR:-/var/backups/cis}"

backup_file() {
	local file="$1"

	if [[ ! -f "$file" ]]; then
		log_warn "Backup skipped, file does not exist: $file"
		return 0
	fi

	mkdir -p "$BACKUP_DIR"
	local ts backup_name backup_path
	ts="$(date +%F-%H%M%S)"
	backup_name="$(basename "$file").$ts"
	backup_path="$BACKUP_DIR/$backup_name"

	cp -p -- "$file" "$backup_path"

	log_success "Backed up $file to $backup_path"
}
