#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

parse_config_only_args "$@" || true
load_config

failures=0
warnings=0
DNS_RESOLVER="${DNS_RESOLVER:-1.1.1.1}"

dig_short() {
  dig @"$DNS_RESOLVER" +short "$@" 2>/dev/null | sed 's/\.$//' | sort -u
}

normalize_txt() {
  tr -d '"[:space:]'
}

normalize_local_dkim() {
  awk '
    /\(/ { in_record=1; sub(/^.*\(/, "") }
    in_record {
      sub(/\).*$/, "")
      gsub(/"/, "")
      gsub(/[[:space:]]/, "")
      printf "%s", $0
    }
    /\)/ { exit }
  ' "$1"
}

contains_line() {
  local expected="$1"
  grep -Fxq "$expected"
}

check_host_ip() {
  local type="$1"
  local host="$2"
  local expected="$3"
  local records
  records="$(dig_short "$host" "$type")"

  if [[ -z "$expected" ]]; then
    if [[ -n "$records" ]]; then
      warn_state "$host $type has records but no expected $type is configured: $(tr '\n' ' ' <<< "$records")"
    else
      ok_state "$host $type intentionally absent"
    fi
    return 0
  fi

  if contains_line "$expected" <<< "$records"; then
    ok_state "$host $type contains $expected"
  else
    fail_state "$host $type missing $expected; got: ${records:-<none>}"
  fi

  local extra
  while IFS= read -r extra; do
    [[ -n "$extra" && "$extra" != "$expected" ]] || continue
    warn_state "$host $type has unexpected extra record: $extra"
  done <<< "$records"
}

check_txt() {
  local name="$1"
  local expected="$2"
  local normalized_expected normalized_records
  normalized_expected="$(normalize_txt <<< "$expected")"
  normalized_records="$(dig @"$DNS_RESOLVER" +short TXT "$name" 2>/dev/null | normalize_txt)"

  if grep -Fq "$normalized_expected" <<< "$normalized_records"; then
    ok_state "$name TXT matches"
  else
    fail_state "$name TXT missing expected value"
  fi
}

printf 'DNS state for %s\n' "$PRIMARY_DOMAIN"
printf 'Resolver: %s\n\n' "$DNS_RESOLVER"

declare -A hosts=()
hosts["$MAIL_HOSTNAME"]=1
hosts["$WEBMAIL_HOSTNAME"]=1
hosts["$DAV_HOSTNAME"]=1

for host in "${!hosts[@]}"; do
  check_host_ip A "$host" "$SERVER_PUBLIC_IPV4"
  check_host_ip AAAA "$host" "${SERVER_PUBLIC_IPV6:-}"
done

mx_records="$(dig_short "$PRIMARY_DOMAIN" MX)"
expected_mx="10 $MAIL_HOSTNAME"
if contains_line "$expected_mx" <<< "$mx_records"; then
  ok_state "$PRIMARY_DOMAIN MX points to $MAIL_HOSTNAME"
else
  fail_state "$PRIMARY_DOMAIN MX missing '$expected_mx'; got: ${mx_records:-<none>}"
fi

check_txt "$PRIMARY_DOMAIN" "v=spf1 mx -all"
check_txt "_dmarc.$PRIMARY_DOMAIN" "v=DMARC1; p=none; rua=mailto:dmarc@$PRIMARY_DOMAIN; adkim=s; aspf=s"

ptr_records="$(dig_short -x "$SERVER_PUBLIC_IPV4")"
if contains_line "$MAIL_HOSTNAME" <<< "$ptr_records"; then
  ok_state "$SERVER_PUBLIC_IPV4 PTR/rDNS points to $MAIL_HOSTNAME"
else
  fail_state "$SERVER_PUBLIC_IPV4 PTR/rDNS missing $MAIL_HOSTNAME; got: ${ptr_records:-<none>}"
fi

if [[ -n "${SERVER_PUBLIC_IPV6:-}" ]]; then
  ptr_records="$(dig_short -x "$SERVER_PUBLIC_IPV6")"
  if contains_line "$MAIL_HOSTNAME" <<< "$ptr_records"; then
    ok_state "$SERVER_PUBLIC_IPV6 PTR/rDNS points to $MAIL_HOSTNAME"
  else
    fail_state "$SERVER_PUBLIC_IPV6 PTR/rDNS missing $MAIL_HOSTNAME; got: ${ptr_records:-<none>}"
  fi
fi

dkim_name="$DKIM_SELECTOR._domainkey.$PRIMARY_DOMAIN"
dkim_file="/etc/mailserver/dkim/$PRIMARY_DOMAIN/$DKIM_SELECTOR.txt"
dns_dkim="$(dig @"$DNS_RESOLVER" +short TXT "$dkim_name" 2>/dev/null | normalize_txt)"
if [[ -r "$dkim_file" ]]; then
  expected_dkim="$(normalize_local_dkim "$dkim_file")"
  if [[ -n "$dns_dkim" && "$dns_dkim" == *"$expected_dkim"* ]]; then
    ok_state "$dkim_name TXT matches generated DKIM key"
  else
    fail_state "$dkim_name TXT missing or different from generated DKIM key"
  fi
elif [[ -f "$dkim_file" ]]; then
  if [[ "$dns_dkim" == *"v=DKIM1"* && "$dns_dkim" == *"p="* ]]; then
    warn_state "$dkim_name TXT exists, but $dkim_file is not readable; run sudo mailserver dns-state to compare exact key"
  else
    fail_state "$dkim_name TXT missing; run sudo mailserver print-dns to read the generated value"
  fi
else
  warn_state "Generated DKIM file not found yet: $dkim_file"
fi

printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
[[ "$failures" -eq 0 ]]
