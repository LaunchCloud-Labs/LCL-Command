#!/usr/bin/env bash
set -euo pipefail
umask 077

CONFIG_FILE="${HOME}/.config/lcl-deploy/env"
SHARED_CONFIG_FILE="${LCL_DEPLOY_SHARED_CONFIG:-/Users/garycolonna/.config/lcl-deploy/shared.env}"
DEFAULT_HOST="ftp.launchcloudlabs.com"
DEFAULT_USER="command@launchcloudlabs.com"
DEFAULT_DEMO_ROOT="${LCL_DEPLOY_DEMO_ROOT:-public_html/demo}"
ADVANCED_CODE="${LCL_DEPLOY_ADVANCED_CODE:-1472}"

usage() {
  cat <<USAGE
Usage:
  lcl-deploy [--dry-run] [--delete] demo <name> <path>
  lcl-deploy [--dry-run] [--delete] path <remote-path> <path> [--code <passcode>]
  lcl-deploy list [remote-path]
  lcl-deploy wizard

Default behavior:
  - demo uploads go to ${DEFAULT_DEMO_ROOT}/<name>
  - advanced path uploads require explicit unlock code ${ADVANCED_CODE}

Environment variables:
  LCL_DEPLOY_HOST        Remote host (defaults to ${DEFAULT_HOST})
  LCL_DEPLOY_USER        Remote username (defaults to ${DEFAULT_USER})
  LCL_DEPLOY_PASS        Remote password
  LCL_DEPLOY_PORT        Optional port override for transport probing and upload
  LCL_DEPLOY_DEMO_ROOT   Override the normal demo root
  LCL_DEPLOY_ADVANCED_CODE Override the advanced-mode unlock code

Config files:
  ${CONFIG_FILE}
  ${SHARED_CONFIG_FILE}
  Store LCL_DEPLOY_HOST / USER / PASS / PORT there with chmod 600 (user file) or ACL-restricted shared access.
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*" >&2
}

prompt_value() {
  local prompt="$1"
  local default="${2-}"
  local value=""

  [[ -t 0 ]] || return 1

  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
    read -r value || return 1
    value=${value:-$default}
  else
    printf '%s: ' "$prompt" >&2
    read -r value || return 1
  fi

  printf '%s' "$value"
}

prompt_secret() {
  local prompt="$1"
  local value=""

  [[ -t 0 ]] || return 1

  printf '%s: ' "$prompt" >&2
  read -r -s value || return 1
  printf '\n' >&2
  printf '%s' "$value"
}

quote_lftp() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//\$/\\$}
  value=${value//\`/\\\`}
  printf '"%s"' "$value"
}

default_port_for() {
  case "$1" in
    sftp) printf '22' ;;
    ftps|ftp) printf '21' ;;
    *) return 1 ;;
  esac
}

port_for() {
  if [[ -n "${LCL_DEPLOY_PORT:-}" ]]; then
    printf '%s' "$LCL_DEPLOY_PORT"
  else
    default_port_for "$1"
  fi
}

write_lftp_prelude() {
  local file="$1"
  local proto="$2"

  cat > "$file" <<PRELUDE
set cmd:fail-exit yes
set net:max-retries 1
set net:reconnect-interval-base 2
set net:timeout 10
set xfer:clobber on
set ssl:check-hostname yes
PRELUDE

  case "$proto" in
    sftp)
      printf '%s\n' 'set sftp:auto-confirm yes' >> "$file"
      ;;
    ftps)
      {
        printf '%s\n' 'set ftp:ssl-force true'
        printf '%s\n' 'set ftp:ssl-protect-data true'
        printf '%s\n' 'set ssl:verify-certificate true'
      } >> "$file"
      ;;
    ftp)
      printf '%s\n' 'set ftp:ssl-allow no' >> "$file"
      ;;
    *)
      die "Unsupported protocol: $proto"
      ;;
  esac
}

write_login_commands() {
  local file="$1"
  local proto="$2"
  local port="$3"

  {
    printf 'open %s\n' "$(quote_lftp "${proto}://${HOST}:${port}")"
    printf 'user %s %s\n' "$(quote_lftp "$USER_NAME")" "$(quote_lftp "$PASSWORD")"
  } >> "$file"
}

probe_transport() {
  local proto="$1"
  local port="$2"
  local script_file="$3"
  local log_file="$4"

  write_lftp_prelude "$script_file" "$proto"
  write_login_commands "$script_file" "$proto" "$port"
  {
    printf '%s\n' 'cls -1'
    printf '%s\n' 'bye'
  } >> "$script_file"

  lftp -f "$script_file" > "$log_file" 2>&1
}

append_excludes() {
  local pattern
  for pattern in \
    '(^|/)\\.git(/|$)' \
    '(^|/)node_modules(/|$)' \
    '(^|/)\\.env($|\\.)' \
    '(^|/)\\.DS_Store$' \
    '(^|/)\\.cache(/|$)' \
    '(^|/)\\.next/cache(/|$)' \
    '(^|/)__pycache__(/|$)' \
    '(^|/)\\.pytest_cache(/|$)' \
    '(^|/)logs?(/|$)' \
    '(^|/)[^/]+\\.log$'
  do
    printf -- '-x %s ' "$(quote_lftp "$pattern")"
  done
}

redact_lftp_output() {
  sed -E 's#://[^/@[:space:]]+(:[^@[:space:]]*)?@#://***:***@#g'
}

sanitize_remote_path() {
  local input="$1"
  [[ -n "$input" ]] || die 'Remote path cannot be empty'
  [[ "$input" != /* ]] || die 'Remote path must be relative to the FTP root'
  [[ "$input" != *'..'* ]] || die 'Remote path cannot contain ..'
  [[ "$input" =~ ^[A-Za-z0-9._/-]+$ ]] || die 'Remote path contains unsupported characters'
  printf '%s' "$input"
}

sanitize_demo_name() {
  local input="$1"
  [[ "$input" =~ ^[A-Za-z0-9._-]+$ ]] || die 'Demo name must contain only letters, numbers, dots, underscores, or hyphens'
  [[ "$input" != '.' && "$input" != '..' ]] || die 'Demo name cannot be . or ..'
  printf '%s' "$input"
}

ensure_tools() {
  command -v lftp >/dev/null 2>&1 || die 'lftp is required but not installed'
}

load_config() {
  if [[ -f "$SHARED_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SHARED_CONFIG_FILE"
  fi

  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi

  HOST="${LCL_DEPLOY_HOST:-$DEFAULT_HOST}"
  USER_NAME="${LCL_DEPLOY_USER:-$DEFAULT_USER}"
  PASSWORD="${LCL_DEPLOY_PASS:-}"
  DEMO_ROOT="${LCL_DEPLOY_DEMO_ROOT:-$DEFAULT_DEMO_ROOT}"
}

ensure_credentials() {
  if [[ -z "${LCL_DEPLOY_USER:-}" && -t 0 ]]; then
    USER_NAME="$(prompt_value 'Username' "$DEFAULT_USER" || printf '%s' "$DEFAULT_USER")"
  fi

  if [[ -z "$PASSWORD" ]]; then
    PASSWORD="$(prompt_secret 'Password' || true)"
    [[ -n "$PASSWORD" ]] || die 'Password is required (set LCL_DEPLOY_PASS or enter it interactively)'
  fi
}

ensure_transport() {
  [[ -n "${SELECTED_PROTO:-}" ]] && return 0

  TMP_DIR="$(mktemp -d -t lcl-deploy.XXXXXX)"
  chmod 700 "$TMP_DIR"
  trap 'rm -rf "$TMP_DIR"' EXIT

  SELECTED_PROTO=""
  SELECTED_PORT=""
  attempts=()

  for proto in sftp ftps ftp; do
    port="$(port_for "$proto")"
    proto_label=$(printf %s "$proto" | tr '[:lower:]' '[:upper:]')
    note "Probing ${proto_label}://${HOST}:${port} ..."
    script_file="$TMP_DIR/${proto}.probe.lftp"
    log_file="$TMP_DIR/${proto}.probe.log"

    if probe_transport "$proto" "$port" "$script_file" "$log_file"; then
      SELECTED_PROTO="$proto"
      SELECTED_PORT="$port"
      return 0
    fi

    summary="$(tail -n 3 "$log_file" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    attempts+=("${proto_label}://${HOST}:${port} -> ${summary:-connection failed}")
  done

  printf 'Unable to connect with any supported transport.\n' >&2
  printf 'Tried, in order:\n' >&2
  local attempt
  for attempt in "${attempts[@]}"; do
    printf '  - %s\n' "$attempt" >&2
  done
  exit 1
}

print_target_summary() {
  local remote_target="$1"
  local local_path="$2"
  local url_path="${SELECTED_PROTO}://${HOST}"
  local default_port
  default_port="$(default_port_for "$SELECTED_PROTO")"
  if [[ "$SELECTED_PORT" != "$default_port" || -n "${LCL_DEPLOY_PORT:-}" ]]; then
    url_path+=":${SELECTED_PORT}"
  fi
  url_path+="/${remote_target}"

  printf 'Remote target: %s\n' "$remote_target"
  printf 'URL-ish path:  %s\n' "$url_path"
  printf 'Local source:  %s\n' "$local_path"
  if (( DRY_RUN )); then
    printf 'Mode:          dry-run\n'
  fi
  if (( DELETE_MODE )); then
    printf 'Delete mode:   enabled\n'
  fi
}

run_upload() {
  local remote_target="$1"
  local local_input_path="$2"
  [[ -d "$local_input_path" ]] || die "Local path is not a directory: $local_input_path"
  local local_path
  local deploy_script

  local_path="$(cd "$local_input_path" && pwd -P)"
  remote_target="$(sanitize_remote_path "$remote_target")"

  ensure_transport
  print_target_summary "$remote_target" "$local_path"

  deploy_script="$TMP_DIR/deploy.lftp"
  write_lftp_prelude "$deploy_script" "$SELECTED_PROTO"
  write_login_commands "$deploy_script" "$SELECTED_PROTO" "$SELECTED_PORT"
  {
    printf 'mkdir -p %s\n' "$(quote_lftp "$remote_target")"
    printf 'mirror -R --verbose=1 '
    (( DRY_RUN )) && printf '%s ' '--dry-run'
    (( DELETE_MODE )) && printf '%s ' '--delete'
    append_excludes
    printf '%s %s\n' "$(quote_lftp "$local_path")" "$(quote_lftp "$remote_target")"
    printf '%s\n' 'bye'
  } >> "$deploy_script"

  local deploy_log="$TMP_DIR/deploy.log"
  local deploy_status=0
  if ! lftp -f "$deploy_script" > "$deploy_log" 2>&1; then
    deploy_status=$?
  fi
  redact_lftp_output < "$deploy_log"
  (( deploy_status == 0 )) || return "$deploy_status"
  printf 'Done. Remote target: %s\n' "$remote_target"
}

list_remote() {
  local remote_target="${1:-$DEMO_ROOT}"
  local list_script
  remote_target="$(sanitize_remote_path "$remote_target")"
  ensure_transport

  list_script="$TMP_DIR/list.lftp"
  write_lftp_prelude "$list_script" "$SELECTED_PROTO"
  write_login_commands "$list_script" "$SELECTED_PROTO" "$SELECTED_PORT"
  {
    printf 'cls -1 %s\n' "$(quote_lftp "$remote_target")"
    printf '%s\n' 'bye'
  } >> "$list_script"

  local list_log="$TMP_DIR/list.log"
  local list_status=0
  if ! lftp -f "$list_script" > "$list_log" 2>&1; then
    list_status=$?
  fi
  redact_lftp_output < "$list_log"
  (( list_status == 0 )) || return "$list_status"
}

unlock_advanced() {
  local provided="${ADVANCED_PASSCODE:-}"
  if [[ -z "$provided" ]]; then
    provided="$(prompt_secret 'Enter advanced deploy code' || true)"
  fi
  [[ "$provided" == "$ADVANCED_CODE" ]] || die 'Advanced deploy unlock failed'
}

choose_local_path() {
  local default_path="${PWD}"
  local chosen
  while true; do
    chosen="$(prompt_value 'Local folder to upload' "$default_path" || true)"
    [[ -n "$chosen" ]] || die 'Local folder is required'
    if [[ -d "$chosen" ]]; then
      printf '%s' "$chosen"
      return 0
    fi
    printf 'That folder does not exist.\n' >&2
  done
}

choose_demo_name() {
  local existing
  printf '\nExisting entries under %s:\n' "$DEMO_ROOT"
  if ! existing="$(list_remote "$DEMO_ROOT" 2>/dev/null || true)"; then
    existing=''
  fi
  if [[ -n "$existing" ]]; then
    printf '%s\n' "$existing"
  else
    printf '  (no entries listed or listing unavailable)\n'
  fi
  printf '\n'
  sanitize_demo_name "$(prompt_value 'Demo subdirectory name' 'test' || true)"
}

choose_common_root() {
  local roots=(
    "$DEMO_ROOT"
    "public_html"
    "public_html/demo"
    "public_html/sites"
    "public_html/internal"
    "internal/demo"
  )
  local i=1 choice
  printf '\nAdvanced destination roots:\n'
  for root in "${roots[@]}"; do
    printf '  %d) %s\n' "$i" "$root"
    i=$((i + 1))
  done
  printf '  m) manual path entry\n\n'

  choice="$(prompt_value 'Choose destination root' '1' || true)"
  if [[ "$choice" == 'm' || "$choice" == 'M' ]]; then
    sanitize_remote_path "$(prompt_value 'Manual remote path' "$DEMO_ROOT" || true)"
    return 0
  fi
  [[ "$choice" =~ ^[0-9]+$ ]] || die 'Invalid advanced root selection'
  (( choice >= 1 && choice <= ${#roots[@]} )) || die 'Invalid advanced root selection'
  printf '%s' "${roots[$((choice - 1))]}"
}

wizard() {
  local action local_path demo_name remote_root remote_target relative_path confirm
  while true; do
    printf '\nLCL Deploy Wizard\n'
    printf '  1) Deploy to demo\n'
    printf '  2) Browse demo directories\n'
    printf '  3) Advanced deploy (requires %s)\n' "$ADVANCED_CODE"
    printf '  q) Quit\n\n'

    action="$(prompt_value 'Selection' '1' || true)"
    case "$action" in
      1)
        local_path="$(choose_local_path)"
        demo_name="$(choose_demo_name)"
        remote_target="${DEMO_ROOT}/${demo_name}"
        printf '\nAbout to deploy to %s\n' "$remote_target"
        confirm="$(prompt_value 'Proceed? [y/N]' 'N' || true)"
        [[ "$confirm" =~ ^[Yy]$ ]] || continue
        run_upload "$remote_target" "$local_path"
        ;;
      2)
        printf '\n'
        list_remote "$DEMO_ROOT"
        ;;
      3)
        unlock_advanced
        local_path="$(choose_local_path)"
        remote_root="$(choose_common_root)"
        printf '\nCurrent listing for %s:\n' "$remote_root"
        list_remote "$remote_root" 2>/dev/null || true
        printf '\n'
        relative_path="$(prompt_value 'Subdirectory under selected root (blank keeps root)' '' || true)"
        if [[ -n "$relative_path" ]]; then
          relative_path="$(sanitize_remote_path "$relative_path")"
          remote_target="${remote_root%/}/${relative_path}"
        else
          remote_target="$remote_root"
        fi
        printf '\nAdvanced target: %s\n' "$remote_target"
        confirm="$(prompt_value 'Proceed with advanced deploy? [y/N]' 'N' || true)"
        [[ "$confirm" =~ ^[Yy]$ ]] || continue
        run_upload "$remote_target" "$local_path"
        ;;
      q|Q)
        exit 0
        ;;
      *)
        printf 'Unknown selection.\n' >&2
        ;;
    esac
  done
}

ensure_tools
load_config

DRY_RUN=0
DELETE_MODE=0
ADVANCED_PASSCODE="${LCL_DEPLOY_CODE:-}"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --delete)
      DELETE_MODE=1
      shift
      ;;
    --code)
      [[ $# -ge 2 ]] || die '--code requires a value'
      ADVANCED_PASSCODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
  POSITIONAL=(wizard)
fi

ensure_credentials

case "${POSITIONAL[0]}" in
  wizard)
    wizard
    ;;
  demo)
    [[ ${#POSITIONAL[@]} -eq 3 ]] || die "Usage: lcl-deploy [--dry-run] [--delete] demo <name> <path>"
    demo_name="$(sanitize_demo_name "${POSITIONAL[1]}")"
    run_upload "${DEMO_ROOT}/${demo_name}" "${POSITIONAL[2]}"
    ;;
  path)
    [[ ${#POSITIONAL[@]} -eq 3 ]] || die "Usage: lcl-deploy [--dry-run] [--delete] path <remote-path> <path> [--code <passcode>]"
    unlock_advanced
    run_upload "${POSITIONAL[1]}" "${POSITIONAL[2]}"
    ;;
  list)
    [[ ${#POSITIONAL[@]} -le 2 ]] || die "Usage: lcl-deploy list [remote-path]"
    list_remote "${POSITIONAL[1]:-$DEMO_ROOT}"
    ;;
  *)
    die "Unknown target: ${POSITIONAL[0]}"
    ;;
esac
