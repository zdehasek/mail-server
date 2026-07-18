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
    info "Would drop PostgreSQL database $MAIL_DB_NAME and role $MAIL_DB_USER"
    return 0
  fi

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
if [[ "$CONFIG_FILE" == /* ]]; then
  warn "This will delete setup config: $CONFIG_FILE"
else
  warn "Setup config path is relative; it will not be deleted automatically: $CONFIG_FILE"
fi
warn "This will delete mailserver backups under: $BACKUP_DIR and $BACKUP_ROOT"
warn "This will remove generated TLS material for: $(unique_tls_names | paste -sd' ' -)"
warn "This will purge installed mail/webmail packages when they are present."

validate_delete_paths

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
