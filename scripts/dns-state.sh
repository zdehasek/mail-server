#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

usage() { usage_line "Usage: mailserver dns-state [--domain example.com] [--skip-dkim] [--skip-ptr] [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
load_config

failures=0
warnings=0
DNS_RESOLVER="${DNS_RESOLVER:-1.1.1.1}"
target_domain="$(normalize_domain "$PRIMARY_DOMAIN")"
skip_dkim="false"
skip_ptr="false"

while [[ "${#POSITIONAL[@]}" -gt 0 ]]; do
  case "${POSITIONAL[0]}" in
    --domain)
      [[ -n "${POSITIONAL[1]:-}" ]] || die "Missing value for --domain."
      target_domain="$(normalize_domain "${POSITIONAL[1]}")"
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    --skip-dkim)
      skip_dkim="true"
      POSITIONAL=("${POSITIONAL[@]:1}")
      ;;
    --skip-ptr)
      skip_ptr="true"
      POSITIONAL=("${POSITIONAL[@]:1}")
      ;;
    *)
      die "Unknown dns-state option: ${POSITIONAL[0]}"
      ;;
  esac
done
validate_domain_or_die "$target_domain"

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
  local expected_record
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

  expected_record="$host. $type $expected"
  if contains_line "$expected" <<< "$records"; then
    ok_state "$expected_record"
  else
    fail_state "$host $type expected: $expected_record; got: ${records:-<none>}"
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
  local expected_record records records_display normalized_expected normalized_records
  expected_record="$name. TXT \"$expected\""
  normalized_expected="$(normalize_txt <<< "$expected")"
  records="$(dig @"$DNS_RESOLVER" +short TXT "$name" 2>/dev/null || true)"
  records_display="$(tr '\n' ' ' <<< "$records" | sed 's/[[:space:]]\+$//')"
  normalized_records="$(normalize_txt <<< "$records")"

  if grep -Fq "$normalized_expected" <<< "$normalized_records"; then
    ok_state "$expected_record"
  else
    fail_state "$name TXT expected: $expected_record; got: ${records_display:-<none>}"
  fi
}

ui_heading "DNS state for $target_domain"
info "Resolver: $DNS_RESOLVER"
ui_blank

declare -A hosts=()
hosts["$MAIL_HOSTNAME"]=1
hosts["$WEBMAIL_HOSTNAME"]=1
hosts["$DAV_HOSTNAME"]=1

for host in "${!hosts[@]}"; do
  check_host_ip A "$host" "$SERVER_PUBLIC_IPV4"
  check_host_ip AAAA "$host" "${SERVER_PUBLIC_IPV6:-}"
done

mx_records="$(dig_short "$target_domain" MX)"
expected_mx="10 $MAIL_HOSTNAME"
expected_mx_record="$target_domain. MX 10 $MAIL_HOSTNAME."
if contains_line "$expected_mx" <<< "$mx_records"; then
  ok_state "$expected_mx_record"
else
  fail_state "$target_domain MX expected: $expected_mx_record; got: ${mx_records:-<none>}"
fi

check_txt "$target_domain" "v=spf1 mx -all"
check_txt "_dmarc.$target_domain" "v=DMARC1; p=none; rua=mailto:dmarc@$target_domain; adkim=s; aspf=s"

if [[ "$skip_ptr" == "true" ]]; then
  warn_state "PTR/rDNS check skipped by --skip-ptr"
else
  ptr_records="$(dig_short -x "$SERVER_PUBLIC_IPV4")"
  if contains_line "$MAIL_HOSTNAME" <<< "$ptr_records"; then
    ok_state "PTR/rDNS $SERVER_PUBLIC_IPV4 -> $MAIL_HOSTNAME"
  else
    fail_state "$SERVER_PUBLIC_IPV4 PTR/rDNS expected: $SERVER_PUBLIC_IPV4 -> $MAIL_HOSTNAME; got: ${ptr_records:-<none>}"
  fi
fi

dkim_name="$DKIM_SELECTOR._domainkey.$target_domain"
dkim_file="$DKIM_ROOT/$target_domain/$DKIM_SELECTOR.txt"
if [[ "$skip_dkim" == "true" ]]; then
  warn_state "DKIM check skipped by --skip-dkim"
else
  dns_dkim_records="$(dig @"$DNS_RESOLVER" +short TXT "$dkim_name" 2>/dev/null || true)"
  dns_dkim_display="$(tr '\n' ' ' <<< "$dns_dkim_records" | sed 's/[[:space:]]\+$//')"
  dns_dkim="$(normalize_txt <<< "$dns_dkim_records")"
  if [[ -r "$dkim_file" ]]; then
    expected_dkim="$(normalize_local_dkim "$dkim_file")"
    expected_dkim_record="$(format_dkim_dns_record_file "$dkim_file" "$target_domain")"
    if [[ -n "$dns_dkim" && "$dns_dkim" == *"$expected_dkim"* ]]; then
      ok_state "$expected_dkim_record"
    else
      fail_state "$dkim_name TXT expected: $expected_dkim_record; got: ${dns_dkim_display:-<none>}"
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
fi

ui_blank
ui_summary "$failures" "$warnings" "$failures failure(s), $warnings warning(s)"
[[ "$failures" -eq 0 ]]
