#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo mailserver set-alias --source source@example.com --dest destination@example.com [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
source_addr=""
dest_addr=""
while [[ "${#POSITIONAL[@]}" -gt 0 ]]; do
  case "${POSITIONAL[0]}" in
    --source)
      [[ -n "${POSITIONAL[1]:-}" ]] || { usage; exit 1; }
      source_addr="${POSITIONAL[1]}"
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    --dest|--destination)
      [[ -n "${POSITIONAL[1]:-}" ]] || { usage; exit 1; }
      dest_addr="${POSITIONAL[1]}"
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    *)
      if [[ -z "$source_addr" ]]; then
        source_addr="${POSITIONAL[0]}"
        POSITIONAL=("${POSITIONAL[@]:1}")
      elif [[ -z "$dest_addr" ]]; then
        dest_addr="${POSITIONAL[0]}"
        POSITIONAL=("${POSITIONAL[@]:1}")
      else
        usage
        exit 1
      fi
      ;;
  esac
done
[[ -n "$source_addr" && -n "$dest_addr" ]] || { usage; exit 1; }
require_root
load_config

domain="${source_addr#*@}"
localpart="${source_addr%@*}"
dest_domain="${dest_addr#*@}"
dest_localpart="${dest_addr%@*}"
[[ "$source_addr" == *@* && -n "$domain" && -n "$localpart" ]] || die "Invalid source email address: $source_addr"
[[ "$dest_addr" == *@* && -n "$dest_domain" && -n "$dest_localpart" ]] || die "Invalid destination email address: $dest_addr"

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would set alias $source_addr -> $dest_addr and deactivate other active destinations for $source_addr"
  exit 0
fi

domain_q="$(sql_quote "$domain")"
source_q="$(sql_quote "$source_addr")"
dest_q="$(sql_quote "$dest_addr")"

sqlite3 "$MAIL_DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO domains(name, active) VALUES('$domain_q', 1)
ON CONFLICT(name) DO UPDATE SET active=1;
SQL

refresh_opendkim_domain_maps "$domain"
reload_or_restart opendkim

sqlite3 "$MAIL_DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
BEGIN;
UPDATE aliases SET active=0 WHERE source='$source_q' AND active=1;
INSERT INTO aliases(domain_id, source, destination, active)
VALUES((SELECT id FROM domains WHERE name='$domain_q'), '$source_q', '$dest_q', 1)
ON CONFLICT(source, destination) DO UPDATE SET domain_id=excluded.domain_id, active=1;
COMMIT;
SQL

info "Alias set: $source_addr -> $dest_addr"
