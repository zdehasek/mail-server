#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { usage_line "Usage: mailserver print-dns [--domain example.com] [--skip-dkim] [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
load_config

target_domain="$(normalize_domain "$PRIMARY_DOMAIN")"
skip_dkim="false"
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
    *)
      die "Unknown print-dns option: ${POSITIONAL[0]}"
      ;;
  esac
done
validate_domain_or_die "$target_domain"

cat <<DNS
Publish these DNS records:

$target_domain. MX 10 $MAIL_HOSTNAME.
DNS

declare -A printed_hosts=()
print_host_record() {
  local host="$1"
  local type="$2"
  local value="$3"
  local key="$host|$type|$value"
  [[ -n "$host" ]] || return 0
  [[ -z "${printed_hosts[$key]:-}" ]] || return 0
  printed_hosts[$key]=1
  printf '%s. %s %s\n' "$host" "$type" "$value"
}

print_host_record "$MAIL_HOSTNAME" A "$SERVER_PUBLIC_IPV4"
print_host_record "$WEBMAIL_HOSTNAME" A "$SERVER_PUBLIC_IPV4"
print_host_record "$DAV_HOSTNAME" A "$SERVER_PUBLIC_IPV4"

print_dkim_record_file() {
  local file="$1"
  local domain="$2"
  local line
  local name
  local value

  line="$(tr '\n' ' ' < "$file" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  [[ -n "$line" ]] || return 0

  if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+IN[[:space:]]+TXT[[:space:]]+(.+)$ ]]; then
    name="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
  elif [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+TXT[[:space:]]+(.+)$ ]]; then
    name="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
  else
    printf '%s\n' "$line"
    return 0
  fi

  name="${name%.}"
  if [[ "$name" != *".$domain" ]]; then
    name="$name.$domain"
  fi
  value="${value%% ; -----*}"
  printf '%s. TXT %s\n' "$name" "$value"
}

cat <<DNS
$target_domain. TXT "v=spf1 mx -all"
_dmarc.$target_domain. TXT "v=DMARC1; p=none; rua=mailto:dmarc@$target_domain; adkim=s; aspf=s"
DNS

if [[ -n "${SERVER_PUBLIC_IPV6:-}" ]]; then
  print_host_record "$MAIL_HOSTNAME" AAAA "$SERVER_PUBLIC_IPV6"
  print_host_record "$WEBMAIL_HOSTNAME" AAAA "$SERVER_PUBLIC_IPV6"
  print_host_record "$DAV_HOSTNAME" AAAA "$SERVER_PUBLIC_IPV6"
fi

dkim_txt="$DKIM_ROOT/$target_domain/$DKIM_SELECTOR.txt"
if [[ "$skip_dkim" == "true" ]]; then
  cat <<DNS

DKIM record:
  Skipped by --skip-dkim.
  Expected name: $DKIM_SELECTOR._domainkey.$target_domain.
DNS
elif [[ ! -f "$dkim_txt" && "$target_domain" == "$(normalize_domain "$PRIMARY_DOMAIN")" ]]; then
  ensure_dkim_key_for_domain "$target_domain"
  print_dkim_record_file "$dkim_txt" "$target_domain"
elif [[ -f "$dkim_txt" ]]; then
  print_dkim_record_file "$dkim_txt" "$target_domain"
elif [[ "$target_domain" == "$(normalize_domain "$PRIMARY_DOMAIN")" ]]; then
  cat <<DNS

DKIM record is not generated yet.
Run sudo mailserver print-dns again to generate it and print the exact TXT value.
DNS
else
  cat <<DNS

DKIM record is not generated yet. Run sudo mailserver add-domain --domain $target_domain, then rerun this command.
Expected name: $DKIM_SELECTOR._domainkey.$target_domain.
DNS
fi

cat <<DNS

Provider PTR/rDNS must be:
$SERVER_PUBLIC_IPV4 -> $MAIL_HOSTNAME
DNS
