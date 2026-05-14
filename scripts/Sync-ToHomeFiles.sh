#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
home_root="$(cd -- "$HOME" && pwd -P)"
manifest_path="$script_dir/home-files.txt"
dry_run=false

usage() {
  printf 'Usage: %s [--manifest PATH] [--dry-run|-n]\n' "$(basename "$0")"
}

write_step() {
  printf '\n==> %s\n' "$1"
}

write_ok() {
  printf '  OK: %s\n' "$1"
}

write_warn() {
  printf '  WARN: %s\n' "$1"
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

resolve_tracked_path() {
  local base_path="$1"
  local relative_path="$2"
  local label="$3"
  local normalized_relative_path

  normalized_relative_path="${relative_path//\\//}"

  case "$normalized_relative_path" in
    /*) die "Manifest entry '$relative_path' must be home-relative" ;;
  esac

  case "/$normalized_relative_path/" in
    *'/../'* | *'/..') die "Manifest entry '$relative_path' escapes the $label root" ;;
  esac

  printf '%s/%s' "$base_path" "$normalized_relative_path"
}

add_result() {
  results+=("$1"$'\t'"$2"$'\t'"$3")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      [[ $# -ge 2 ]] || die '--manifest requires a path'
      manifest_path="$2"
      shift 2
      ;;
    --dry-run | -n)
      dry_run=true
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -f "$manifest_path" ]] || die "Manifest file not found: $manifest_path"

entries=()
while IFS= read -r line || [[ -n "$line" ]]; do
  entry="$(trim "$line")"
  [[ -n "$entry" ]] || continue
  [[ "$entry" == \#* ]] && continue
  entries+=("$entry")
done < "$manifest_path"

if [[ ${#entries[@]} -eq 0 ]]; then
  write_warn "No tracked files listed in $manifest_path"
  exit 0
fi

results=()
write_step "Syncing ${#entries[@]} tracked file(s)"

for entry in "${entries[@]}"; do
  source_path="$(resolve_tracked_path "$repo_root" "$entry" 'repo')"
  destination_path="$(resolve_tracked_path "$home_root" "$entry" 'home')"

  if [[ -f "$source_path" ]]; then
    if [[ -f "$destination_path" ]] && cmp -s -- "$source_path" "$destination_path"; then
      write_ok "Unchanged $entry"
      add_result "$entry" 'Unchanged' 'Repo and home files already match'
      continue
    fi

    destination_directory="$(dirname -- "$destination_path")"
    if [[ ! -d "$destination_directory" ]]; then
      if [[ "$dry_run" == true ]]; then
        write_warn "Skipped $entry"
        add_result "$entry" 'Skipped' 'Directory creation previewed'
        continue
      fi

      mkdir -p -- "$destination_directory"
    fi

    if [[ "$dry_run" == true ]]; then
      write_warn "Skipped $entry"
      add_result "$entry" 'Skipped' 'Copy previewed'
      continue
    fi

    cp -f -- "$source_path" "$destination_path"
    write_ok "Synced $entry"
    add_result "$entry" 'Synced' 'Copied from repo into home directory'
    continue
  fi

  if [[ -e "$source_path" ]]; then
    die "Manifest entry '$entry' is not a file in the repo"
  fi

  if [[ -f "$destination_path" ]]; then
    if [[ "$dry_run" == true ]]; then
      write_warn "Skipped $entry"
      add_result "$entry" 'Skipped' 'Deletion previewed'
      continue
    fi

    printf "Repo source for '%s' is missing.\nDelete '%s' from the home directory? [y/N] " "$entry" "$destination_path"
    read -r confirmation
    case "$confirmation" in
      y | Y | yes | YES)
        rm -f -- "$destination_path"
        write_ok "Removed $entry"
        add_result "$entry" 'Removed' 'Repo source missing and home file deleted after confirmation'
        ;;
      *)
        write_warn "Kept $entry"
        add_result "$entry" 'Skipped' 'Repo source missing; user declined deletion'
        ;;
    esac
    continue
  fi

  write_warn "Missing source for $entry"
  add_result "$entry" 'Skipped' 'Source file missing from repo and no home copy to delete'
done

printf '\nSummary\n'
printf '%-40s  %-10s  %s\n' 'Path' 'Status' 'Detail'
for result in "${results[@]}"; do
  IFS=$'\t' read -r path status detail <<< "$result"
  printf '%-40s  %-10s  %s\n' "$path" "$status" "$detail"
done
