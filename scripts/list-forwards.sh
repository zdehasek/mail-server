#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { usage_line "Usage: sudo mailserver forwards ls [--domain example.com] [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
domain=""
while [[ "${#POSITIONAL[@]}" -gt 0 ]]; do
  case "${POSITIONAL[0]}" in
    --domain)
      [[ -n "${POSITIONAL[1]:-}" ]] || { usage; exit 1; }
      domain="$(normalize_domain "${POSITIONAL[1]}")"
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done
require_root
load_config

where_clause="a.active=true AND u.active=true"
if [[ -n "$domain" ]]; then
  validate_domain_or_die "$domain"
  domain_q="$(sql_quote "$domain")"
  where_clause+=" AND d.name='$domain_q'"
fi

psql_mail <<SQL
SELECT
  CASE a.active WHEN true THEN 'active' ELSE 'inactive' END AS status,
  d.name AS domain,
  a.source,
  a.destination
FROM aliases a
JOIN domains d ON d.id = a.domain_id
JOIN users u ON u.email = a.source AND u.active = true
WHERE $where_clause
ORDER BY d.name, a.source, a.destination;
SQL
