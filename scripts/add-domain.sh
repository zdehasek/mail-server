#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { usage_line "Usage: sudo mailserver domains add --domain example.com [--alias-dest admin@example.com] [--no-default-aliases] [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
domain=""
alias_dest=""
create_default_aliases="true"
while [[ "${#POSITIONAL[@]}" -gt 0 ]]; do
  case "${POSITIONAL[0]}" in
    --domain)
      [[ -n "${POSITIONAL[1]:-}" ]] || { usage; exit 1; }
      domain="${POSITIONAL[1]}"
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    --alias-dest|--alias-destination)
      [[ -n "${POSITIONAL[1]:-}" ]] || { usage; exit 1; }
      alias_dest="${POSITIONAL[1]}"
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    --no-default-aliases)
      create_default_aliases="false"
      POSITIONAL=("${POSITIONAL[@]:1}")
      ;;
    *)
      if [[ -z "$domain" ]]; then
        domain="${POSITIONAL[0]}"
        POSITIONAL=("${POSITIONAL[@]:1}")
      else
        usage
        exit 1
      fi
      ;;
  esac
done
[[ -n "$domain" ]] || { usage; exit 1; }
require_root
load_config

domain="$(normalize_domain "$domain")"
validate_domain_or_die "$domain"
alias_dest="${alias_dest:-$ADMIN_EMAIL}"
if [[ "$create_default_aliases" == "true" ]]; then
  [[ "$alias_dest" == *@* ]] || die "Default alias destination must be an email address: $alias_dest"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would activate mail domain $domain"
  if [[ "$create_default_aliases" == "true" ]]; then
    info "Would add standard aliases postmaster@$domain, abuse@$domain, dmarc@$domain -> $alias_dest"
  fi
  exit 0
fi

refresh_opendkim_domain_maps "$domain"
reload_or_restart opendkim

domain_q="$(sql_quote "$domain")"
alias_dest_q="$(sql_quote "$alias_dest")"
psql_mail <<SQL
INSERT INTO domains(name, active) VALUES('$domain_q', true)
ON CONFLICT(name) DO UPDATE SET active=true;
SQL

if [[ "$create_default_aliases" == "true" ]]; then
  for alias_localpart in postmaster abuse dmarc; do
    alias_q="$(sql_quote "$alias_localpart@$domain")"
    psql_mail <<SQL
INSERT INTO aliases(domain_id, source, destination, active)
VALUES((SELECT id FROM domains WHERE name='$domain_q'), '$alias_q', '$alias_dest_q', true)
ON CONFLICT(source, destination) DO UPDATE SET active=true;
SQL
  done
fi

info "Mail domain active: $domain"
if [[ "$create_default_aliases" == "true" ]]; then
  info "Standard aliases ready: postmaster@$domain abuse@$domain dmarc@$domain -> $alias_dest"
fi
if [[ "$domain" != "$(normalize_domain "$PRIMARY_DOMAIN")" ]]; then
  info "Add mailboxes with: sudo mailserver users add --user user@$domain"
  info "Print DNS records with: sudo mailserver print-dns --domain $domain"
fi
