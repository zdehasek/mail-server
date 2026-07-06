#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo mailserver add-forward --source mailbox@example.com --dest destination@example.com [--allow-mailbox-source] [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
source_addr=""
dest_addr=""
allow_mailbox_source="false"
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
    --allow-mailbox-source)
      allow_mailbox_source="true"
      POSITIONAL=("${POSITIONAL[@]:1}")
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
  info "Would add forward $source_addr -> $dest_addr"
  exit 0
fi

source_q="$(sql_quote "$source_addr")"
mailbox_count="$(psql_mail_scalar -c "SELECT COUNT(*) FROM users WHERE email='$source_q' AND active=true;")"
if [[ "$mailbox_count" -gt 0 && "$allow_mailbox_source" != "true" ]]; then
  die "$source_addr is an active mailbox. Re-run with --allow-mailbox-source to redirect delivery away from the local mailbox."
fi

domain_q="$(sql_quote "$domain")"
dest_q="$(sql_quote "$dest_addr")"

psql_mail <<SQL
INSERT INTO domains(name, active) VALUES('$domain_q', true)
ON CONFLICT(name) DO UPDATE SET active=true;
SQL

refresh_opendkim_domain_maps "$domain"
reload_or_restart opendkim

psql_mail <<SQL
BEGIN;
UPDATE aliases SET active=false WHERE source='$source_q' AND active=true;
INSERT INTO aliases(domain_id, source, destination, active)
VALUES((SELECT id FROM domains WHERE name='$domain_q'), '$source_q', '$dest_q', true)
ON CONFLICT(source, destination) DO UPDATE SET domain_id=excluded.domain_id, active=true;
COMMIT;
SQL

info "Forward ready: $source_addr -> $dest_addr"
