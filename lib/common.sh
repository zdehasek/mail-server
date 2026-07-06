#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG:-${ENV_FILE:-}}"
DRY_RUN="false"
ASSUME_YES="false"
FORCE="false"
BACKUP_ROOT="/var/backups/mailserver"
STATE_DIR="/etc/mailserver/install-state"
MANAGED_HEADER="# Managed by mail-server installer. Manual changes may be overwritten."

use_color() {
  [[ -n "${NO_COLOR:-}" ]] && return 1
  [[ -n "${FORCE_COLOR:-}" && "${FORCE_COLOR:-}" != "0" ]] && return 0
  [[ -n "${CLICOLOR_FORCE:-}" && "${CLICOLOR_FORCE:-}" != "0" ]] && return 0
  [[ ( -t 1 || -t 2 ) && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]
}

style_text() {
  local color="$1"
  shift
  if use_color; then
    printf '\033[%sm%s\033[0m' "$color" "$*"
  else
    printf '%s' "$*"
  fi
}

log_line() {
  local level="$1"
  local color="$2"
  local icon="$3"
  local line
  shift 3
  line="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $icon $level $*"
  printf '%s\n' "$(style_text "$color" "$line")"
}

log() { log_line "LOG  " 36 "• " "$*"; }
info() { log_line "INFO " 36 "ℹ️ " "$*"; }
warn() { log_line "WARN " "38;5;208" "⚠️ " "$*" >&2; }
die() { log_line "ERROR" 31 "❌" "$*" >&2; exit 1; }

ok_state() {
  printf '%s\n' "$(style_text 32 "✅ OK    $*")"
}
warn_state() {
  printf '%s\n' "$(style_text "38;5;208" "⚠️  WARN  $*")"
  : "${warnings:=0}"
  warnings=$((warnings + 1))
}
fail_state() {
  printf '%s\n' "$(style_text 31 "❌ FAIL  $*")"
  : "${failures:=0}"
  failures=$((failures + 1))
}

usage_common() {
  cat <<'USAGE'
Common options:
  --config PATH       Path to config.env
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
      --force)
        # shellcheck disable=SC2034 # Read by sourced phase/preflight scripts.
        FORCE="true"
        shift
        ;;
      --help|-h) usage_common; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root, usually with sudo."
}

config_home() {
  local sudo_home

  if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    sudo_home="$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)"
    if [[ -n "$sudo_home" ]]; then
      printf '%s\n' "$sudo_home"
      return 0
    fi
  fi

  if [[ -n "${HOME:-}" ]]; then
    printf '%s\n' "$HOME"
    return 0
  fi

  getent passwd "$(id -un)" | cut -d: -f6
}

default_config_file() {
  printf '%s/config.env\n' "${MAILSERVER_CONFIG_DIR:-$(config_home)/.email-server}"
}

load_config() {
  [[ -n "$CONFIG_FILE" ]] || CONFIG_FILE="$(default_config_file)"
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
  : "${PRIMARY_MAILBOX:=}"
  : "${PRIMARY_MAILBOX_FULL_NAME:=$PRIMARY_MAILBOX}"
  : "${PRIMARY_MAILBOX_PASSWORD:=}"
  : "${PRIMARY_MAILBOX_PASSWORD_FILE:=/etc/mailserver/secrets/primary-mailbox-password}"
  : "${SECONDARY_DOMAINS:=}"
  : "${DKIM_ROOT:=/etc/mailserver/dkim}"
  : "${PRIMARY_ALIAS_ADDRESSES:=$POSTMASTER_ADDRESS $ABUSE_ADDRESS dmarc@$PRIMARY_DOMAIN admin@$PRIMARY_DOMAIN}"
  : "${MAIL_DB_PATH:=/etc/mailserver/mail.sqlite}"
  : "${MAIL_DB_NAME:=mailserver}"
  : "${MAIL_DB_USER:=mailserver}"
  : "${MAIL_DB_HOST:=127.0.0.1}"
  : "${MAIL_DB_PASSWORD_FILE:=/etc/mailserver/secrets/postgresql-mailserver-password}"
  SOGO_SERVER_NAMES="$WEBMAIL_HOSTNAME"
  if [[ "$DAV_HOSTNAME" != "$WEBMAIL_HOSTNAME" ]]; then
    SOGO_SERVER_NAMES+=" $DAV_HOSTNAME"
  fi
  export SOGO_SERVER_NAMES
  if [[ "${ENABLE_RSPAMD:-true}" == "true" ]]; then
    RSPAMD_MILTER=", inet:127.0.0.1:11332"
  else
    RSPAMD_MILTER=""
  fi
}

mail_domains() {
  local domain seen=" "
  local secondary_domains=()
  IFS=' ' read -r -a secondary_domains <<< "$SECONDARY_DOMAINS"
  for domain in "$PRIMARY_DOMAIN" "${secondary_domains[@]}"; do
    [[ -n "$domain" ]] || continue
    domain="${domain,,}"
    if [[ "$seen" == *" $domain "* ]]; then
      continue
    fi
    seen+="$domain "
    printf '%s\n' "$domain"
  done
}

validate_domain_name() {
  local domain="$1"
  domain="${domain,,}"
  [[ "$domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]]
}

domain_is_managed() {
  local needle="${1,,}"
  local domain
  while IFS= read -r domain; do
    [[ "$domain" == "$needle" ]] && return 0
  done < <(mail_domains)
  return 1
}

require_managed_domain() {
  local domain="${1,,}"
  domain_is_managed "$domain" && return 0
  die "Domain is not configured: $domain. Add it to SECONDARY_DOMAINS or run: mailserver add-domain --domain $domain"
}

sync_configured_domains() {
  local domain domain_q
  while IFS= read -r domain; do
    domain_q="$(sql_quote "$domain")"
    psql_mail -c "INSERT INTO domains(name, active) VALUES('$domain_q', true) ON CONFLICT(name) DO UPDATE SET active=true;"
  done < <(mail_domains)
}

config_value() {
  local value="$1"
  if [[ "$value" =~ ^[A-Za-z0-9_./:@%+=,-]*$ ]]; then
    printf '%s\n' "$value"
  else
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//\$/\\\$}"
    value="${value//\`/\\\`}"
    printf '"%s"\n' "$value"
  fi
}

set_config_entry_or_append() {
  local file="$1"
  local key="$2"
  local value
  value="$(config_value "$3")"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf 'DRY-RUN: set %s=%s in %s\n' "$key" "$value" "$file"
    return 0
  fi
  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^$key=.*|$key=$value|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}

require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Required config variable is empty: $name"
}

validate_config() {
  local required=(
    MAIL_HOSTNAME PRIMARY_DOMAIN ADMIN_EMAIL WEBMAIL_HOSTNAME DAV_HOSTNAME SERVER_PUBLIC_IPV4
    VMAIL_UID VMAIL_GID VMAIL_ROOT MAIL_DB_NAME MAIL_DB_USER MAIL_DB_HOST MAIL_DB_PASSWORD_FILE
    LETSENCRYPT_STAGING ENABLE_UFW ENABLE_FAIL2BAN ENABLE_RSPAMD ENABLE_CLAMAV
    POSTMASTER_ADDRESS ABUSE_ADDRESS DKIM_SELECTOR
  )
  local name
  for name in "${required[@]}"; do require_var "$name"; done

  local domain
  while IFS= read -r domain; do
    validate_domain_name "$domain" || die "Invalid mail domain: $domain"
  done < <(mail_domains)
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
    MAIL_HOSTNAME PRIMARY_DOMAIN ADMIN_EMAIL WEBMAIL_HOSTNAME DAV_HOSTNAME SOGO_SERVER_NAMES SERVER_PUBLIC_IPV4 SERVER_PUBLIC_IPV6
    VMAIL_UID VMAIL_GID VMAIL_ROOT MAIL_DB_PATH MAIL_DB_NAME MAIL_DB_USER MAIL_DB_HOST MAIL_DB_PASSWORD MAIL_DB_PASSWORD_FILE DOVECOT_SQL_CONNECTION_BLOCK DOVECOT_SQL_CONNECT DKIM_SELECTOR
    POSTMASTER_ADDRESS ABUSE_ADDRESS TIMEZONE UFW_RESET_RULES SSH_PORT SSH_ALLOW_USERS SSH_ALLOW_USERS_DIRECTIVE
    BACKUP_DIR BACKUP_RETENTION_DAYS BACKUP_CRON_SCHEDULE
    RSPAMD_MILTER
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
# Source template: ${src#"$ROOT_DIR"/}
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

ensure_mail_db_password() {
  if [[ -n "${MAIL_DB_PASSWORD:-}" ]]; then
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    MAIL_DB_PASSWORD="dry-run-postgresql-password"
    export MAIL_DB_PASSWORD
    return 0
  fi
  if [[ ! -f "$MAIL_DB_PASSWORD_FILE" ]]; then
    install -d -m 0700 "$(dirname "$MAIL_DB_PASSWORD_FILE")"
    openssl rand -hex 32 > "$MAIL_DB_PASSWORD_FILE"
    chmod 0600 "$MAIL_DB_PASSWORD_FILE"
  fi
  MAIL_DB_PASSWORD="$(tr -d '\n' < "$MAIL_DB_PASSWORD_FILE")"
  export MAIL_DB_PASSWORD
}

psql_mail() {
  ensure_mail_db_password
  PGPASSWORD="$MAIL_DB_PASSWORD" psql -v ON_ERROR_STOP=1 -h "$MAIL_DB_HOST" -U "$MAIL_DB_USER" -d "$MAIL_DB_NAME" "$@"
}

psql_mail_scalar() {
  psql_mail -At "$@"
}

dovecot_sql_connection_block() {
  ensure_mail_db_password
  cat <<EOF
pgsql $MAIL_DB_HOST {
  parameters {
    user = $MAIL_DB_USER
    password = $MAIL_DB_PASSWORD
    dbname = $MAIL_DB_NAME
  }
}
EOF
}

dovecot_sql_connect() {
  ensure_mail_db_password
  printf 'host=%s dbname=%s user=%s password=%s\n' "$MAIL_DB_HOST" "$MAIL_DB_NAME" "$MAIL_DB_USER" "$MAIL_DB_PASSWORD"
}

sql_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "%s" "$value"
}

normalize_domain() {
  local domain="$1"
  printf '%s\n' "${domain,,}"
}

validate_domain_or_die() {
  local domain="$1"
  [[ "$domain" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ && "$domain" == *.* && "$domain" != *..* ]] || die "Invalid domain: $domain"
}

configured_mail_domains() {
  local primary db_domains extra
  primary="$(normalize_domain "$PRIMARY_DOMAIN")"
  {
    printf '%s\n' "$primary"
    if command -v psql >/dev/null 2>&1; then
      if ! db_domains="$(psql_mail_scalar -c "SELECT lower(name) FROM domains WHERE active=true ORDER BY name;" 2>&1)"; then
        db_domains=""
      fi
      printf '%s\n' "$db_domains"
    fi
    for extra in "$@"; do
      [[ -n "$extra" ]] || continue
      normalize_domain "$extra"
    done
  } | awk 'NF && !seen[$0]++'
}

ensure_dkim_key_for_domain() {
  local domain="$1"
  local dkim_dir="/etc/mailserver/dkim/$domain"
  local private_key="$dkim_dir/$DKIM_SELECTOR.private"

  validate_domain_or_die "$domain"
  run mkdir -p "$dkim_dir"
  if [[ "$DRY_RUN" != "true" && ! -f "$private_key" ]]; then
    command -v opendkim-genkey >/dev/null 2>&1 || die "opendkim-genkey is required to generate DKIM for $domain. Install OpenDKIM first."
    opendkim-genkey -b 2048 -d "$domain" -s "$DKIM_SELECTOR" -D "$dkim_dir"
  fi

  if [[ "$DRY_RUN" != "true" && -f "$private_key" ]]; then
    if getent passwd opendkim >/dev/null 2>&1; then
      chown -R opendkim:opendkim "$dkim_dir"
    fi
    chmod 0600 "$private_key"
  fi
}

refresh_opendkim_domain_maps() {
  local domain_lines
  local domains=()
  local domain
  local key_table=""
  local signing_table=""
  local trusted_hosts=""
  local host
  declare -A trusted_seen=()

  domain_lines="$(configured_mail_domains "$@")"
  mapfile -t domains <<< "$domain_lines"
  [[ "${#domains[@]}" -gt 0 ]] || die "No mail domains configured for DKIM."

  run mkdir -p /etc/opendkim /etc/mailserver/dkim

  for host in 127.0.0.1 ::1 localhost "$MAIL_HOSTNAME"; do
    [[ -n "$host" ]] || continue
    trusted_hosts+="$host"$'\n'
    trusted_seen["$host"]=1
  done

  for domain in "${domains[@]}"; do
    domain="$(normalize_domain "$domain")"
    validate_domain_or_die "$domain"
    ensure_dkim_key_for_domain "$domain"
    key_table+="$DKIM_SELECTOR._domainkey.$domain $domain:$DKIM_SELECTOR:/etc/mailserver/dkim/$domain/$DKIM_SELECTOR.private"$'\n'
    signing_table+="*@$domain $DKIM_SELECTOR._domainkey.$domain"$'\n'
    if [[ -z "${trusted_seen[$domain]:-}" ]]; then
      trusted_hosts+="$domain"$'\n'
      trusted_seen["$domain"]=1
    fi
  done

  write_file /etc/opendkim/key.table "${key_table%$'\n'}"
  write_file /etc/opendkim/signing.table "${signing_table%$'\n'}"
  write_file /etc/opendkim/trusted.hosts "${trusted_hosts%$'\n'}"
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf "%s" "$value"
}

curl_config_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf "%s" "$value"
}

parse_config_only_args() {
  CONFIG_FILE="${CONFIG:-${ENV_FILE:-$(default_config_file)}}"
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
