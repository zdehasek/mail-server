#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { usage_line "Usage: sudo mailserver list-domains [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
[[ "${#POSITIONAL[@]}" -eq 0 ]] || { usage; exit 1; }
require_root
load_config

primary_q="$(sql_quote "$(normalize_domain "$PRIMARY_DOMAIN")")"
psql_mail <<SQL
SELECT
  CASE d.active WHEN true THEN 'active' ELSE 'inactive' END AS status,
  CASE d.name WHEN '$primary_q' THEN 'yes' ELSE '' END AS primary_domain,
  d.name AS domain,
  COALESCE(u.mailboxes, 0) AS mailboxes,
  COALESCE(a.aliases, 0) AS aliases
FROM domains d
LEFT JOIN (
  SELECT domain_id, COUNT(*) AS mailboxes
  FROM users
  WHERE active=true
  GROUP BY domain_id
) u ON u.domain_id = d.id
LEFT JOIN (
  SELECT domain_id, COUNT(*) AS aliases
  FROM aliases
  WHERE active=true
  GROUP BY domain_id
) a ON a.domain_id = d.id
ORDER BY d.active DESC, d.name;
SQL
