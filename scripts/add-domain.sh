#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=../lib/dkim.sh
source "$ROOT_DIR/lib/dkim.sh"

usage() { echo "Usage: sudo mailserver add-domain --domain example.com [--config PATH] [--dry-run]"; }

domain=""
POSITIONAL=()
CONFIG_FILE="${CONFIG:-${ENV_FILE:-$(default_config_file)}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --assume-yes|-y) ASSUME_YES="true"; shift ;;
    --domain) domain="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ -z "$domain" && "${#POSITIONAL[@]}" -eq 1 ]]; then
  domain="${POSITIONAL[0]}"
elif [[ "${#POSITIONAL[@]}" -gt 0 ]]; then
  usage
  exit 1
fi
[[ -n "$domain" ]] || { usage; exit 1; }

load_config
[[ "$DRY_RUN" == "true" ]] || require_root

domain="${domain,,}"
validate_domain_name "$domain" || die "Invalid domain: $domain"

if ! domain_is_managed "$domain"; then
  if [[ "$domain" == "${PRIMARY_DOMAIN,,}" ]]; then
    info "Domain is already the primary domain: $domain"
  else
    SECONDARY_DOMAINS="$({
      primary_domain="${PRIMARY_DOMAIN,,}"
      while IFS= read -r configured_domain; do
        [[ "$configured_domain" == "$primary_domain" ]] || printf '%s\n' "$configured_domain"
      done < <(mail_domains)
      printf '%s\n' "$domain"
    } | awk 'NF { value=tolower($0); if (!seen[value]++) print value }' | paste -sd ' ' -)"
    set_config_entry_or_append "$CONFIG_FILE" SECONDARY_DOMAINS "$SECONDARY_DOMAINS"
    info "Added $domain to SECONDARY_DOMAINS in $CONFIG_FILE"
  fi
else
  info "Domain is already configured: $domain"
fi

if [[ -f "$MAIL_DB_PATH" || "$DRY_RUN" == "true" ]]; then
  sync_configured_domains
else
  warn "Mail database not found at $MAIL_DB_PATH; domain will be seeded during install."
fi

if command -v opendkim-genkey >/dev/null 2>&1 || [[ "$DRY_RUN" == "true" ]]; then
  sync_dkim_domains
else
  warn "opendkim-genkey is not installed; DKIM keys will be generated during install."
fi

if [[ "$DRY_RUN" != "true" ]]; then
  if systemctl cat opendkim >/dev/null 2>&1; then
    reload_or_restart opendkim
  fi
  if command -v postfix >/dev/null 2>&1; then
    run postfix reload || warn "Postfix reload failed; check service state manually."
  fi
fi

info "Domain ready: $domain"
"$ROOT_DIR/scripts/print-dns.sh" --config "$CONFIG_FILE"
