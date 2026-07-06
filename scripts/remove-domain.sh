#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo mailserver remove-domain --domain example.com [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
if [[ "${POSITIONAL[0]:-}" == "--domain" ]]; then
  [[ -n "${POSITIONAL[1]:-}" && "${#POSITIONAL[@]}" -eq 2 ]] || { usage; exit 1; }
  POSITIONAL=("${POSITIONAL[1]}")
fi
[[ "${#POSITIONAL[@]}" -eq 1 ]] || { usage; exit 1; }
require_root
load_config

domain="$(normalize_domain "${POSITIONAL[0]}")"
primary_domain="$(normalize_domain "$PRIMARY_DOMAIN")"
validate_domain_or_die "$domain"
[[ "$domain" != "$primary_domain" ]] || die "Refusing to remove PRIMARY_DOMAIN: $domain"

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would deactivate mail domain $domain, its mailboxes, and its aliases"
  exit 0
fi

domain_q="$(sql_quote "$domain")"
domain_changes="$(psql_mail_scalar <<SQL
WITH deactivated_users AS (
  UPDATE users
  SET active=false
  WHERE domain_id=(SELECT id FROM domains WHERE name='$domain_q') AND active=true
  RETURNING 1
),
deactivated_aliases AS (
  UPDATE aliases
  SET active=false
  WHERE domain_id=(SELECT id FROM domains WHERE name='$domain_q') AND active=true
  RETURNING 1
),
deactivated_domain AS (
  UPDATE domains SET active=false WHERE name='$domain_q' AND active=true RETURNING 1
)
SELECT COUNT(*) FROM deactivated_domain;
SQL
)"
if [[ "$domain_changes" -eq 0 ]]; then
  die "Active mail domain not found: $domain"
fi

info "Mail domain deactivated: $domain"
info "Maildirs were left on disk for recovery."
refresh_opendkim_domain_maps
reload_or_restart opendkim
