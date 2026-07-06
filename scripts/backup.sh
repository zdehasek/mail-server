#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo mailserver backup [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
require_root
load_config

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_path="$BACKUP_DIR/mailserver-$timestamp.tar.gz"
staging_dir=""

cleanup() {
  [[ -n "$staging_dir" && -d "$staging_dir" ]] && rm -rf "$staging_dir"
}
trap cleanup EXIT

run mkdir -p "$BACKUP_DIR"
run chmod 0700 "$BACKUP_DIR"

paths=(
  /etc/mailserver
  /etc/letsencrypt
  /etc/postfix
  /etc/dovecot
  /etc/opendkim
  /etc/opendmarc.conf
  /etc/rspamd
  /etc/sogo
  /etc/nginx/sites-available
  /etc/nginx/sites-enabled
  "$VMAIL_ROOT"
)

existing=()
for path in "${paths[@]}"; do
  [[ -e "$path" ]] && existing+=("$path")
done

[[ "${#existing[@]}" -gt 0 ]] || die "No backup paths exist yet. Has the server been installed?"

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would write backup to $backup_path"
  info "Would create PostgreSQL dump for $MAIL_DB_NAME"
  printf 'DRY-RUN: tar -czf %q' "$backup_path"
  printf ' %q' "${existing[@]}"
  printf ' -C <staging> postgresql'
  printf '\n'
else
  staging_dir="$(mktemp -d)"
  mkdir -p "$staging_dir/postgresql"
  ensure_mail_db_password
  PGPASSWORD="$MAIL_DB_PASSWORD" pg_dump -h "$MAIL_DB_HOST" -U "$MAIL_DB_USER" "$MAIL_DB_NAME" > "$staging_dir/postgresql/$MAIL_DB_NAME.sql"

  tar -czf "$backup_path" --absolute-names "${existing[@]}" -C "$staging_dir" postgresql
  chmod 0600 "$backup_path"
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'mailserver-*.tar.gz' -mtime "+$BACKUP_RETENTION_DAYS" -delete
fi

info "Backup ready: $backup_path"
