#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
remove_source="$(< "$ROOT_DIR/scripts/remove.sh")"

assert_contains() {
  local needle="$1"
  if [[ "$remove_source" != *"$needle"* ]]; then
    printf 'Expected scripts/remove.sh to contain:\n%s\n' "$needle" >&2
    exit 1
  fi
}

assert_contains 'PURGE_BACKUP_DIR="${MAILSERVER_PURGE_BACKUP_DIR:-/var/backups/mailserver-purge}"'
assert_contains 'backup_mail_database_before_drop'
assert_contains 'pg_dump --clean --if-exists "$MAIL_DB_NAME"'
assert_contains 'pg_dumpall --globals-only'
assert_contains 'refusing to drop $MAIL_DB_NAME without a database backup'
assert_contains 'Purge database backup path would be deleted by purge'

printf 'remove purge database backup wiring ok\n'
