#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo mailserver add-alias --source source@example.com --dest destination@example.com [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
[[ "${#POSITIONAL[@]}" -eq 2 ]] || { usage; exit 1; }
require_root
load_config

source_addr="${POSITIONAL[0]}"
dest_addr="${POSITIONAL[1]}"
domain="${source_addr#*@}"
[[ "$source_addr" == *@* && "$dest_addr" == *@* ]] || die "Aliases must be email addresses."

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would add alias $source_addr -> $dest_addr"
  exit 0
fi

domain_q="$(sql_quote "$domain")"
source_q="$(sql_quote "$source_addr")"
dest_q="$(sql_quote "$dest_addr")"

refresh_opendkim_domain_maps "$domain"
reload_or_restart opendkim

sqlite3 "$MAIL_DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
INSERT INTO domains(name, active) VALUES('$domain_q', 1)
ON CONFLICT(name) DO UPDATE SET active=1;
INSERT INTO aliases(domain_id, source, destination, active)
VALUES((SELECT id FROM domains WHERE name='$domain_q'), '$source_q', '$dest_q', 1)
ON CONFLICT(source, destination) DO UPDATE SET active=1;
SQL

info "Alias ready: $source_addr -> $dest_addr"
