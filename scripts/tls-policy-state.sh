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
  local expected="$2"
  local expected_value="$3"
  local value
  value="$(dig +short TXT "$name" | tr -d '"' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  if [[ "$value" == "$expected_value" ]]; then
    ok_state "$expected"
  else
    warn_state "$name TXT expected: $expected; got: ${value:-<none>}"
  fi
}

check_tlsa() {
  local name="$1"
  local expected="$2"
  local expected_value="$3"
  local value
  value="$(dig +short TLSA "$name" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  if [[ "$value" == "$expected_value" ]]; then
    ok_state "$expected"
  else
    warn_state "$name TLSA expected: $expected; got: ${value:-<none>}"
  fi
}

check_host() {
  local name="$1"
  local type="$2"
  local expected="$3"
  local value
  value="$(dig +short "$type" "$name" | sed 's/\.$//' | sort -u)"
  if grep -Fxq "$expected" <<< "$value"; then
    ok_state "$name. $type $expected"
  else
    warn_state "$name $type expected: $name. $type $expected; got: ${value:-<none>}"
  fi
}

ui_heading "TLS policy state for $target_domain"
ui_blank
check_txt "_mta-sts.$target_domain" "_mta-sts.$target_domain. TXT \"v=STSv1; id=1\"" "v=STSv1; id=1"
check_host "mta-sts.$target_domain" A "$SERVER_PUBLIC_IPV4"
if [[ -n "${SERVER_PUBLIC_IPV6:-}" ]]; then
  check_host "mta-sts.$target_domain" AAAA "$SERVER_PUBLIC_IPV6"
fi
check_txt "_smtp._tls.$target_domain" "_smtp._tls.$target_domain. TXT \"v=TLSRPTv1; rua=mailto:postmaster@$target_domain\"" "v=TLSRPTv1; rua=mailto:postmaster@$target_domain"
tlsa_cert_file="${MAILSERVER_TLSA_CERT_FILE:-/etc/letsencrypt/live/$MAIL_HOSTNAME/fullchain.pem}"
if tlsa_record="$(tlsa_record_from_cert_file "$tlsa_cert_file" "$MAIL_HOSTNAME")"; then
  check_tlsa "_25._tcp.$MAIL_HOSTNAME" "$tlsa_record" "${tlsa_record#_25._tcp.$MAIL_HOSTNAME. TLSA }"
else
  warn_state "DANE TLSA can be checked after the certificate exists: $tlsa_cert_file"
fi

ui_blank
ui_summary "$failures" "$warnings" "$failures failure(s), $warnings warning(s)"
[[ "$failures" -eq 0 ]]
