#!/usr/bin/env bash
set -euo pipefail

skip_opencode=false
skip_copilot=false
skip_codex=false
skip_rtk=false
results=()

usage() {
  printf 'Usage: %s [--skip-opencode] [--skip-copilot] [--skip-codex] [--skip-rtk]\n' "$(basename "$0")"
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

add_result() {
  results+=("$1"$'\t'"$2"$'\t'"$3")
}

version_ge() {
  local current="$1"
  local latest="$2"
  local current_major current_minor current_patch latest_major latest_minor latest_patch

  IFS=. read -r current_major current_minor current_patch <<< "$current"
  IFS=. read -r latest_major latest_minor latest_patch <<< "$latest"

  (( current_major > latest_major )) && return 0
  (( current_major < latest_major )) && return 1
  (( current_minor > latest_minor )) && return 0
  (( current_minor < latest_minor )) && return 1
  (( current_patch >= latest_patch ))
}

rtk_asset_name() {
  local os arch

  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os:$arch" in
    Darwin:arm64 | Darwin:aarch64)
      printf 'rtk-aarch64-apple-darwin.tar.gz'
      ;;
    Darwin:x86_64)
      printf 'rtk-x86_64-apple-darwin.tar.gz'
      ;;
    Linux:arm64 | Linux:aarch64)
      printf 'rtk-aarch64-unknown-linux-gnu.tar.gz'
      ;;
    Linux:x86_64)
      printf 'rtk-x86_64-unknown-linux-musl.tar.gz'
      ;;
    *)
      return 1
      ;;
  esac
}

invoke_update_command() {
  local name="$1"
  local command_name="$2"
  shift 2

  if ! command_path="$(command -v "$command_name" 2>/dev/null)"; then
    write_warn "$name is not installed; skipping"
    add_result "$name" 'Skipped' 'Command not found'
    return
  fi

  write_step "Updating $name"
  "$command_path" "$@"
  write_ok "$name updated"
  add_result "$name" 'Updated' "$command_name $*"
}

update_rtk_cli() {
  if ! command_path="$(command -v rtk 2>/dev/null)"; then
    write_warn 'RTK is not installed; skipping'
    add_result 'RTK CLI' 'Skipped' 'Command not found'
    return
  fi

  write_step 'Checking RTK release information'
  current_version_text="$($command_path --version | sed -n '1p')"
  if [[ ! "$current_version_text" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    die "Could not parse RTK version from '$current_version_text'"
  fi

  current_version="${BASH_REMATCH[1]}"
  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/rtk-ai/rtk/releases/latest)"
  latest_version="${latest_url##*/v}"

  if ! [[ "$latest_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Could not parse latest RTK version from '$latest_url'"
  fi

  if version_ge "$current_version" "$latest_version"; then
    write_ok "RTK already current ($current_version)"
    add_result 'RTK CLI' 'Current' "Version $current_version"
    return
  fi

  if ! asset_name="$(rtk_asset_name)"; then
    write_warn "RTK updates are not supported on $(uname -s)/$(uname -m); skipping"
    add_result 'RTK CLI' 'Skipped' "Unsupported platform $(uname -s)/$(uname -m)"
    return
  fi

  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/rtk-update.XXXXXX")"
  archive_path="$temp_root/$asset_name"
  extract_path="$temp_root/extract"
  download_url="https://github.com/rtk-ai/rtk/releases/download/v$latest_version/$asset_name"

  cleanup_rtk_update() {
    rm -rf -- "$temp_root"
  }
  trap cleanup_rtk_update EXIT

  mkdir -p -- "$extract_path"

  write_step "Updating RTK from $current_version to $latest_version"
  curl -fL -o "$archive_path" -- "$download_url"
  tar -xzf "$archive_path" -C "$extract_path"

  downloaded_binary=""
  while IFS= read -r candidate; do
    downloaded_binary="$candidate"
    break
  done < <(find "$extract_path" -type f -name rtk -perm -111)

  [[ -n "$downloaded_binary" ]] || die 'Downloaded RTK archive did not contain an executable rtk binary'

  cp -f -- "$downloaded_binary" "$command_path"
  chmod +x "$command_path"
  write_ok "RTK updated at $command_path"
  add_result 'RTK CLI' 'Updated' "$current_version -> $latest_version"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-opencode)
      skip_opencode=true
      shift
      ;;
    --skip-copilot)
      skip_copilot=true
      shift
      ;;
    --skip-codex)
      skip_codex=true
      shift
      ;;
    --skip-rtk)
      skip_rtk=true
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

if [[ "$skip_opencode" == false ]]; then
  invoke_update_command 'OpenCode CLI' opencode upgrade
fi

if [[ "$skip_copilot" == false ]]; then
  invoke_update_command 'GitHub Copilot CLI' copilot update
fi

if [[ "$skip_codex" == false ]]; then
  invoke_update_command 'Codex CLI' npm install -g '@openai/codex@latest'
fi

if [[ "$skip_rtk" == false ]]; then
  update_rtk_cli
fi

printf '\nSummary\n'
printf '%-20s  %-10s  %s\n' 'Name' 'Status' 'Detail'
if [[ ${#results[@]} -eq 0 ]]; then
  printf '%-20s  %-10s  %s\n' '-' '-' 'No updates requested'
else
  for result in "${results[@]}"; do
    IFS=$'\t' read -r name status detail <<< "$result"
    printf '%-20s  %-10s  %s\n' "$name" "$status" "$detail"
  done
fi
