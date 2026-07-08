#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  sudo mailserver restore --list [--config PATH]
  sudo mailserver restore --inspect ARCHIVE [--config PATH]
  sudo mailserver restore --validate ARCHIVE [--config PATH]
  sudo mailserver restore --extract ARCHIVE --target DIR [--config PATH]

Restore is intentionally non-destructive. It validates or extracts a backup into
a staging directory so an operator can review it before copying data back.
USAGE
}

parse_config_only_args "$@" || { usage; exit 0; }
require_root
load_config

action=""
archive=""
target_dir=""

while [[ "${#POSITIONAL[@]}" -gt 0 ]]; do
  case "${POSITIONAL[0]}" in
    --list|list)
      action="list"
      POSITIONAL=("${POSITIONAL[@]:1}")
      ;;
    --inspect|inspect)
      action="inspect"
      archive="${POSITIONAL[1]:-}"
      [[ -n "$archive" ]] || die "Missing archive path for --inspect."
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    --validate|validate)
      action="validate"
      archive="${POSITIONAL[1]:-}"
      [[ -n "$archive" ]] || die "Missing archive path for --validate."
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    --extract|extract)
      action="extract"
      archive="${POSITIONAL[1]:-}"
      [[ -n "$archive" ]] || die "Missing archive path for --extract."
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    --target)
      target_dir="${POSITIONAL[1]:-}"
      [[ -n "$target_dir" ]] || die "Missing value for --target."
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    *)
      die "Unknown restore option: ${POSITIONAL[0]}"
      ;;
  esac
done

[[ -n "$action" ]] || { usage; exit 1; }

list_backups() {
  if [[ ! -d "$BACKUP_DIR" ]]; then
    warn "Backup directory does not exist: $BACKUP_DIR"
    return 0
  fi

  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'mailserver-*.tar.gz' -printf '%T@ %p\n' \
    | sort -nr \
    | awk '{ $1=""; sub(/^ /, ""); print }'
}

require_archive() {
  [[ -f "$archive" ]] || die "Backup archive not found: $archive"
  [[ "$archive" == *.tar.gz ]] || die "Expected a .tar.gz backup archive: $archive"
}

validate_archive() {
  local listing
  require_archive
  tar -tzf "$archive" >/dev/null
  listing="$(tar -tzf "$archive")"
  grep -qx 'postgresql/' <<< "$listing" || die "Backup is missing PostgreSQL dump directory."
  grep -qx "postgresql/$MAIL_DB_NAME.sql" <<< "$listing" || die "Backup is missing PostgreSQL dump: postgresql/$MAIL_DB_NAME.sql"
  grep -qx '/etc/mailserver/' <<< "$listing" || die "Backup is missing /etc/mailserver."
  grep -qx '/etc/postfix/' <<< "$listing" || die "Backup is missing /etc/postfix."
  grep -qx '/etc/dovecot/' <<< "$listing" || die "Backup is missing /etc/dovecot."
  grep -qx "${VMAIL_ROOT%/}/" <<< "$listing" || die "Backup is missing mail storage root: $VMAIL_ROOT"
  info "Backup archive is readable: $archive"
}

case "$action" in
  list)
    list_backups
    ;;
  inspect)
    require_archive
    tar -tzf "$archive" | sed -n '1,240p'
    ;;
  validate)
    validate_archive
    ;;
  extract)
    validate_archive
    [[ -n "$target_dir" ]] || die "Missing --target DIR for extract."
    if [[ "$DRY_RUN" == "true" ]]; then
      info "Would extract $archive into $target_dir"
      exit 0
    fi
    install -d -m 0700 "$target_dir"
    tar -xzf "$archive" -C "$target_dir"
    info "Backup extracted into: $target_dir"
    info "Review extracted files before manually restoring PostgreSQL, config, or mail data."
    ;;
esac
