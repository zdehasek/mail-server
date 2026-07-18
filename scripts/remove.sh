#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() {
  usage_line "Usage: sudo mailserver remove --purge [--config PATH] [--dry-run]"
}

purge="false"
CONFIG_FILE="${CONFIG:-${ENV_FILE:-$(default_config_file)}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --purge)
      purge="true"
      shift
      ;;
    --assume-yes|-y|--yes)
      die "remove --purge never accepts $1. Type the confirmation sentence instead."
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown remove option: $1"
      ;;
  esac
done

[[ "$purge" == "true" ]] || die "Refusing to remove anything without --purge. Usage: sudo mailserver remove --purge"
require_root
load_config
PURGE_BACKUP_DIR="${MAILSERVER_PURGE_BACKUP_DIR:-/var/backups/mailserver-purge}"

phases=(
  00-preflight
  10-packages
  20-system
  30-certs
  40-database
  50-dovecot
  60-postfix
  70-dkim-dmarc-rspamd
  80-sogo
  92-primary-mailbox
  95-security
  99-verify
)

red_line() {
  ui_line_err "1;31" "$*"
}

danger_banner() {
  red_line "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  red_line "DANGER: mailserver remove --purge will permanently delete data."
  red_line "DANGER: this is not a repair command and it is not reversible."
  red_line "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
}

confirmation_sentence() {
  printf 'delete all mailserver data for %s\n' "$PRIMARY_DOMAIN"
}

unique_tls_names() {
  local seen=" "
  local name
  for name in "$MAIL_HOSTNAME" "$WEBMAIL_HOSTNAME" "$DAV_HOSTNAME"; do
    [[ -n "$name" && "$seen" != *" $name "* ]] || continue
    seen+="$name "
    printf '%s\n' "$name"
  done
}

read_confirmation() {
  local expected="$1"
  local reply=""
  local tty_fd_open="false"

  if [[ ! -t 0 ]]; then
    if { exec 3</dev/tty; } 2>/dev/null; then
      tty_fd_open="true"
    else
      die "Interactive confirmation is required. Re-run from a terminal."
    fi
  fi

  ui_blank >&2
  ui_line_err "1;31" "Type this exact sentence to continue:"
  ui_line_err "1;31" "$expected"
  printf '> ' >&2

  if [[ "$tty_fd_open" == "true" ]]; then
    IFS= read -r reply <&3 || true
    exec 3<&-
  else
    IFS= read -r reply || true
  fi

  [[ "$reply" == "$expected" ]] || die "Confirmation did not match. Nothing was removed."
}

assert_safe_delete_path() {
  local path="$1"
  [[ "$path" == /* ]] || die "Refusing non-absolute delete path: $path"
  case "$path" in
    ""|"/"|"/etc"|"/var"|"/var/lib"|"/var/log"|"/var/backups"|"/home"|"/srv"|"/opt"|"/usr"|"/usr/local")
      die "Refusing unsafe delete path: $path"
      ;;
  esac
}

run_rm() {
  local path="$1"
  assert_safe_delete_path "$path"
  run rm -rf -- "$path"
}

validate_delete_paths() {
  local path
  for path in "$VMAIL_ROOT" "$BACKUP_DIR" "$BACKUP_ROOT" /etc/mailserver /var/www/letsencrypt; do
    assert_safe_delete_path "$path"
  done
  if [[ "$CONFIG_FILE" == /* ]]; then
    assert_safe_delete_path "$CONFIG_FILE"
  fi
}

validate_purge_backup_dir() {
  [[ "$PURGE_BACKUP_DIR" == /* ]] || die "Purge database backup path must be absolute: $PURGE_BACKUP_DIR"
  case "$PURGE_BACKUP_DIR" in
    ""|"/"|"/etc"|"/var"|"/var/lib"|"/var/log"|"/var/backups"|"/home"|"/srv"|"/opt"|"/usr"|"/usr/local")
      die "Refusing unsafe purge database backup path: $PURGE_BACKUP_DIR"
      ;;
  esac
  case "$PURGE_BACKUP_DIR/" in
    "$BACKUP_DIR"/*|"$BACKUP_ROOT"/*|"$VMAIL_ROOT"/*|/etc/mailserver/*|/var/www/letsencrypt/*)
      die "Purge database backup path would be deleted by purge: $PURGE_BACKUP_DIR"
      ;;
  esac
}

service_unit_exists() {
  local service="$1"
  systemctl list-unit-files "$service.service" --no-legend 2>/dev/null | grep -q "^$service\\.service"
}

stop_disable_service() {
  local service="$1"
  if service_unit_exists "$service"; then
    run systemctl disable --now "$service" || true
  else
    info "Service not installed, skipping: $service"
  fi
}

mail_database_exists() {
  local exists
  exists="$(sudo -u postgres psql -At -v ON_ERROR_STOP=1 -v db="$MAIL_DB_NAME" <<'SQL'
SELECT 1 FROM pg_database WHERE datname = :'db';
SQL
)"
  [[ "$exists" == "1" ]]
}

backup_mail_database_before_drop() {
  local timestamp dump_path globals_path

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  dump_path="$PURGE_BACKUP_DIR/$MAIL_DB_NAME-$timestamp.sql.gz"
  globals_path="$PURGE_BACKUP_DIR/postgresql-globals-$timestamp.sql.gz"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would write PostgreSQL purge safety dump: $dump_path"
    info "Would write PostgreSQL role/global dump: $globals_path"
    return 0
  fi

  if ! command -v pg_dump >/dev/null 2>&1; then
    die "pg_dump not found; refusing to drop $MAIL_DB_NAME without a database backup"
  fi
  if ! command -v pg_dumpall >/dev/null 2>&1; then
    die "pg_dumpall not found; refusing to drop $MAIL_DB_NAME without role/global backup"
  fi

  if ! mail_database_exists; then
    info "PostgreSQL database $MAIL_DB_NAME does not exist; skipping database backup"
    return 0
  fi

  install -d -o root -g root -m 0700 "$PURGE_BACKUP_DIR"
  sudo -u postgres pg_dump --clean --if-exists "$MAIL_DB_NAME" | gzip -c > "$dump_path"
  sudo -u postgres pg_dumpall --globals-only | gzip -c > "$globals_path"
  chmod 0600 "$dump_path" "$globals_path"
  info "PostgreSQL purge safety dump ready: $dump_path"
  info "PostgreSQL role/global dump ready: $globals_path"
}

drop_mail_database() {
  if ! command -v psql >/dev/null 2>&1; then
    warn "PostgreSQL client not found; skipping database drop"
    return 0
  fi
  if ! getent passwd postgres >/dev/null 2>&1; then
    warn "postgres system user not found; skipping database drop"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    backup_mail_database_before_drop
    info "Would drop PostgreSQL database $MAIL_DB_NAME and role $MAIL_DB_USER"
    return 0
  fi

  backup_mail_database_before_drop

  sudo -u postgres psql -v ON_ERROR_STOP=1 -v db="$MAIL_DB_NAME" -v role="$MAIL_DB_USER" <<'SQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = :'db';
DROP DATABASE IF EXISTS :"db";
DROP ROLE IF EXISTS :"role";
SQL
}

reset_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    run ufw --force reset
    run ufw --force disable
  else
    info "ufw not installed, skipping firewall reset"
  fi
}

reload_ssh_after_cleanup() {
  if command -v sshd >/dev/null 2>&1; then
    if /usr/sbin/sshd -t; then
      run systemctl reload ssh || run systemctl reload sshd || true
    else
      warn "SSH config test failed after removing mailserver hardening; inspect sshd config manually"
    fi
  fi
}

danger_banner
warn "This will stop and disable mail services."
warn "This will delete mailbox data under: $VMAIL_ROOT"
warn "This will drop PostgreSQL database: $MAIL_DB_NAME"
warn "This will drop PostgreSQL role: $MAIL_DB_USER"
warn "This will delete installer state and secrets under: /etc/mailserver"
warn "This will first write a PostgreSQL safety dump under: $PURGE_BACKUP_DIR"
if [[ "$CONFIG_FILE" == /* ]]; then
  warn "This will delete setup config: $CONFIG_FILE"
else
  warn "Setup config path is relative; it will not be deleted automatically: $CONFIG_FILE"
fi
warn "This will delete mailserver backups under: $BACKUP_DIR and $BACKUP_ROOT"
warn "This will remove generated TLS material for: $(unique_tls_names | paste -sd' ' -)"
warn "This will purge installed mail/webmail packages when they are present."

validate_delete_paths
validate_purge_backup_dir

if [[ "$DRY_RUN" != "true" ]]; then
  read_confirmation "$(confirmation_sentence)"
else
  warn "Dry run only. No data will be removed."
fi

for ((idx=${#phases[@]} - 1; idx >= 0; idx--)); do
  phase="${phases[$idx]}"
  info "Removing phase $phase"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/phases/$phase.sh"
  declare -F down >/dev/null || die "Phase $phase does not define down()"
  down
  unset -f up down phase_packages phase_removable_packages
done

info "Mailserver purge complete. Run mailserver init to start again from defaults."
