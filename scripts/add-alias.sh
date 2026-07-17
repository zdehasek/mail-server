#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { usage_line "Usage: sudo mailserver aliases add --source source@example.com --dest destination@example.com [--config PATH]"; }
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

psql_mail <<SQL
INSERT INTO domains(name, active) VALUES('$domain_q', true)
ON CONFLICT(name) DO UPDATE SET active=true;
INSERT INTO aliases(domain_id, source, destination, active)
VALUES((SELECT id FROM domains WHERE name='$domain_q'), '$source_q', '$dest_q', true)
ON CONFLICT(source, destination) DO UPDATE SET active=true;
SQL

info "Alias ready: $source_addr -> $dest_addr"
