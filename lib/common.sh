#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE=""
DRY_RUN="false"
ASSUME_YES="false"
FORCE="false"
BACKUP_ROOT="/var/backups/mailserver"
STATE_DIR="/etc/mailserver/install-state"
MANAGED_HEADER="# Managed by mail-server installer. Manual changes may be overwritten."

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*" >&2; }
die() { log "ERROR: $*" >&2; exit 1; }

usage_common() {
  cat <<'USAGE'
Common options:
  --config PATH       Path to mail.env
  --dry-run           Print actions without changing the host
  --assume-yes        Do not prompt for confirmation
  --force             Continue past selected preflight failures
USAGE
}

parse_common_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config) CONFIG_FILE="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN="true"; shift ;;
      --assume-yes|-y) ASSUME_YES="true"; shift ;;
      --force) FORCE="true"; shift ;;
      --help|-h) usage_common; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root, usually with sudo."
}

load_config() {
  [[ -n "$CONFIG_FILE" ]] || die "Missing --config PATH."
  [[ -f "$CONFIG_FILE" ]] || die "Config file not found: $CONFIG_FILE"
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  set_config_defaults
  validate_config
}

set_config_defaults() {
  : "${ENABLE_SSH_HARDENING:=true}"
  : "${UFW_RESET_RULES:=true}"
  : "${SSH_PORT:=22}"
  : "${SSH_ALLOW_USERS:=}"
  : "${BACKUP_DIR:=/var/backups/mailserver-data}"
  : "${BACKUP_RETENTION_DAYS:=14}"
  : "${BACKUP_CRON_SCHEDULE:=17 3 * * *}"
  : "${SSH_ALLOW_USERS_DIRECTIVE:=}"
}

require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Required config variable is empty: $name"
}

validate_config() {
  local required=(
    MAIL_HOSTNAME PRIMARY_DOMAIN ADMIN_EMAIL WEBMAIL_HOSTNAME DAV_HOSTNAME SERVER_PUBLIC_IPV4
    VMAIL_UID VMAIL_GID VMAIL_ROOT MAIL_DB_PATH ROUNDCUBE_VERSION ROUNDCUBE_URL ROUNDCUBE_SHA256
    LETSENCRYPT_STAGING ENABLE_UFW ENABLE_FAIL2BAN ENABLE_RSPAMD ENABLE_CLAMAV
    POSTMASTER_ADDRESS ABUSE_ADDRESS DKIM_SELECTOR
  )
  local name
  for name in "${required[@]}"; do require_var "$name"; done
}

confirm() {
  local prompt="$1"
  [[ "$ASSUME_YES" == "true" ]] && return 0
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf 'DRY-RUN: %q' "$1"
    shift || true
    local arg
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf '\n'
    return 0
  fi
  "$@"
}

mark_done() {
  local name="$1"
  run mkdir -p "$STATE_DIR"
  run touch "$STATE_DIR/$name.done"
}

is_done() {
  [[ -f "$STATE_DIR/$1.done" ]]
}

backup_file() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  local stamp dest
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  dest="$BACKUP_ROOT/$stamp${path}"
  run mkdir -p "$(dirname "$dest")"
  run cp -a "$path" "$dest"
}

write_file() {
  local path="$1"
  local content="$2"
  backup_file "$path"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf 'DRY-RUN: write %s\n' "$path"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
}

replace_tokens() {
  local file="$1"
  local content
  content="$(<"$file")"
  local vars=(
    MAIL_HOSTNAME PRIMARY_DOMAIN ADMIN_EMAIL WEBMAIL_HOSTNAME DAV_HOSTNAME SERVER_PUBLIC_IPV4 SERVER_PUBLIC_IPV6
    VMAIL_UID VMAIL_GID VMAIL_ROOT MAIL_DB_PATH ROUNDCUBE_VERSION ROUNDCUBE_URL ROUNDCUBE_SHA256 ROUNDCUBE_DES_KEY DKIM_SELECTOR
    POSTMASTER_ADDRESS ABUSE_ADDRESS TIMEZONE UFW_RESET_RULES SSH_PORT SSH_ALLOW_USERS SSH_ALLOW_USERS_DIRECTIVE
    BACKUP_DIR BACKUP_RETENTION_DAYS BACKUP_CRON_SCHEDULE
  )
  local name value token
  for name in "${vars[@]}"; do
    token="__${name}__"
    value="${!name:-}"
    content="${content//${token}/${value}}"
  done
  printf '%s\n' "$content"
}

render_template() {
  local src="$1"
  local dest="$2"
  [[ -f "$src" ]] || die "Template not found: $src"
  local body
  body="$(replace_tokens "$src")"
  write_file "$dest" "$MANAGED_HEADER
# Source template: ${src#$ROOT_DIR/}
$body"
}

install_packages() {
  local packages=("$@")
  run apt-get update
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

reload_or_restart() {
  local service="$1"
  if systemctl is-active --quiet "$service"; then
    run systemctl reload "$service" || run systemctl restart "$service"
  else
    run systemctl restart "$service"
  fi
}

service_enable_now() {
  run systemctl enable --now "$1"
}

sqlite_mail() {
  run sqlite3 "$MAIL_DB_PATH" "$@"
}

sql_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "%s" "$value"
}

parse_config_only_args() {
  CONFIG_FILE="./mail.env"
  POSITIONAL=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config) CONFIG_FILE="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN="true"; shift ;;
      --assume-yes|-y) ASSUME_YES="true"; shift ;;
      --help|-h) return 1 ;;
      *) POSITIONAL+=("$1"); shift ;;
    esac
  done
}
