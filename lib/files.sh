#!/usr/bin/env bash

ensure_directory() {
	local dir="$1"
	mkdir -p "$dir"
}

file_exists() {
	[[ -f "$1" ]]
}

firectory_exists() {
	[[ -d "$1" ]]
}
