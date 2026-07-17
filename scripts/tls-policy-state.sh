#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { usage_line "Usage: mailserver tls-policy-state [--domain example.com] [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
load_config

target_domain="$PRIMARY_DOMAIN"
while [[ "${#POSITIONAL[@]}" -gt 0 ]]; do
  case "${POSITIONAL[0]}" in
    --domain)
      target_domain="$(normalize_domain "${POSITIONAL[1]:-}")"
      [[ -n "$target_domain" ]] || die "Missing value for --domain."
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    *)
      die "Unknown tls-policy-state option: ${POSITIONAL[0]}"
      ;;
  esac
done

command -v dig >/dev/null 2>&1 || die "dig is required."

warnings=0
failures=0

check_txt() {
  local name="$1"
  local label="$2"
  local value
  value="$(dig +short TXT "$name" | tr -d '"')"
  if [[ -n "$value" ]]; then
    ok_state "$label: $value"
  else
    warn_state "$label missing: $name"
  fi
}

check_host() {
  local name="$1"
  local label="$2"
  if dig +short A "$name" | grep -q . || dig +short AAAA "$name" | grep -q .; then
    ok_state "$label resolves: $name"
  else
    warn_state "$label does not resolve: $name"
  fi
}

ui_heading "TLS policy state for $target_domain"
ui_blank
check_txt "_mta-sts.$target_domain" "MTA-STS TXT"
check_host "mta-sts.$target_domain" "MTA-STS policy host"
check_txt "_smtp._tls.$target_domain" "SMTP TLS reporting TXT"
check_txt "_25._tcp.$MAIL_HOSTNAME" "DANE TLSA for MX"

ui_blank
ui_summary "$failures" "$warnings" "$failures failure(s), $warnings warning(s)"
[[ "$failures" -eq 0 ]]
