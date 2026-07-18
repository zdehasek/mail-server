#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

usage() {
  usage_line "Usage: sudo mailserver apply-cloudflare-dns [--domain example.com] [--dry-run] [--config PATH]"
}

# shellcheck disable=SC2034 # Read by load_config from lib/common.sh.
CONFIG_FILE="${CONFIG:-${ENV_FILE:-$(default_config_file)}}"
target_domain=""
token=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      # shellcheck disable=SC2034 # Read by load_config from lib/common.sh.
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --domain)
      target_domain="$(normalize_domain "${2:-}")"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown apply-cloudflare-dns option: $1"
      ;;
  esac
done

load_config
target_domain="${target_domain:-$(normalize_domain "$PRIMARY_DOMAIN")}"
validate_domain_or_die "$target_domain"

prompt_cloudflare_token() {
  local reply
  if [[ ! -t 0 ]]; then
    if ! exec 3</dev/tty 2>/dev/null; then
      die "Cloudflare API token is required. Re-run from a terminal."
    fi
    printf 'Cloudflare API token: ' > /dev/tty
    IFS= read -r -s reply <&3 || true
    exec 3<&-
  else
    printf 'Cloudflare API token: ' > /dev/tty
    IFS= read -r -s reply < /dev/tty || true
  fi
  printf '\n' > /dev/tty
  [[ -n "$reply" ]] || die "Cloudflare API token was empty."
  printf '%s\n' "$reply"
}

ensure_cloudflare_tools() {
  local missing=()
  local tool

  for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done

  [[ "${#missing[@]}" -gt 0 ]] || return 0
  [[ "$EUID" -eq 0 ]] || die "Install missing Cloudflare DNS tools first: ${missing[*]}"
  command -v apt-get >/dev/null 2>&1 || die "Install missing Cloudflare DNS tools first: ${missing[*]}"

  warn "Installing required Cloudflare DNS tools: ${missing[*]}"
  run env DEBIAN_FRONTEND=noninteractive apt-get update
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  hash -r
}

if [[ "$DRY_RUN" != "true" ]]; then
  ensure_cloudflare_tools
  token="$(prompt_cloudflare_token)"
fi

json_is_success() {
  jq -e '.success == true' >/dev/null <<< "$1"
}

json_first_id() {
  jq -r '.result[0].id // empty' <<< "$1"
}

json_error_message() {
  local message
  message="$(jq -r '[.errors[]?.message] | join("; ")' <<< "$1" 2>/dev/null || true)"
  printf '%s\n' "${message:-unknown Cloudflare API error}"
}

json_first_record_id() {
  local json="$1"
  local mode="$2"
  local name="$3"
  local type="$4"
  local content="${5:-}"
  jq -r \
    --arg mode "$mode" \
    --arg name "$name" \
    --arg type "$type" \
    --arg content "$content" \
    '.result[]
      | select(.name == $name and .type == $type)
      | select(
          ($mode == "exact" and .content == $content)
          or ($mode == "spf" and (.content | ascii_downcase | startswith("v=spf1")))
          or ($mode == "same-name")
        )
      | .id' <<< "$json" | head -n 1
}

json_escape() {
  jq -Rn --arg value "$1" '$value'
}

cf_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local response body status message
  local curl_args=(-sS -X "$method" "https://api.cloudflare.com/client/v4$path" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -w $'\n%{http_code}')
  if [[ -n "$data" ]]; then
    curl_args+=("--data" "$data")
  fi
  response="$(curl "${curl_args[@]}")"
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ "$status" =~ ^2 ]] && json_is_success "$body"; then
    printf '%s\n' "$body"
    return 0
  fi
  message="$(json_error_message "$body")"
  die "Cloudflare API $method $path failed with HTTP $status: ${message:-unknown Cloudflare API error}"
}

resolve_zone_id() {
  local zone_name="$target_domain"
  local response found

  if [[ "$DRY_RUN" == "true" ]]; then
    printf '%s\n' "dry-run-zone"
    return 0
  fi

  while [[ "$zone_name" == *.* ]]; do
    response="$(cf_api GET "/zones?name=$zone_name&status=active&per_page=1")"
    found="$(json_first_id "$response")"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return 0
    fi
    zone_name="${zone_name#*.}"
  done

  die "Could not find an active Cloudflare zone for $target_domain. Check that the token has Zone:Zone Read permission."
}

record_json() {
  local type="$1"
  local name="$2"
  local content="$3"
  local priority="${4:-}"
  local json
  json="{\"type\":$(json_escape "$type"),\"name\":$(json_escape "$name"),\"content\":$(json_escape "$content"),\"ttl\":1"
  case "$type" in
    A|AAAA|CNAME)
      json+=",\"proxied\":false"
      ;;
    MX)
      json+=",\"priority\":$priority"
      ;;
  esac
  json+="}"
  printf '%s\n' "$json"
}

upsert_record() {
  local type="$1"
  local name="$2"
  local content="$3"
  local priority="${4:-}"
  local zone="$5"
  local response exact_id replace_id replace_mode payload

  [[ -n "$name" && -n "$content" ]] || return 0

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ "$type" == "MX" ]]; then
      info "Would upsert Cloudflare DNS: $name. MX $priority $content."
    else
      info "Would upsert Cloudflare DNS: $name. $type $content"
    fi
    return 0
  fi

  response="$(cf_api GET "/zones/$zone/dns_records?type=$type&name=$name&per_page=100")"
  exact_id="$(json_first_record_id "$response" exact "$name" "$type" "$content")"
  if [[ -n "$exact_id" ]]; then
    info "Cloudflare DNS already correct: $name $type"
    return 0
  fi

  replace_mode="same-name"
  if [[ "$type" == "TXT" && "$name" == "$target_domain" ]]; then
    replace_mode="spf"
  elif [[ "$type" == "TXT" ]]; then
    replace_mode="same-name"
  fi

  if [[ "$replace_mode" == "spf" ]]; then
    replace_id="$(json_first_record_id "$response" spf "$name" "$type" "$content")"
  else
    replace_id="$(json_first_record_id "$response" same-name "$name" "$type" "$content")"
  fi

  payload="$(record_json "$type" "$name" "$content" "$priority")"
  if [[ -n "$replace_id" ]]; then
    cf_api PATCH "/zones/$zone/dns_records/$replace_id" "$payload" >/dev/null
    info "Updated Cloudflare DNS: $name $type"
  else
    cf_api POST "/zones/$zone/dns_records" "$payload" >/dev/null
    info "Created Cloudflare DNS: $name $type"
  fi
}

declare -A added_hosts=()
add_host_records() {
  local host="$1"
  local zone="$2"
  [[ -n "$host" ]] || return 0
  [[ -z "${added_hosts[$host]:-}" ]] || return 0
  added_hosts[$host]=1
  # shellcheck disable=SC2153 # Required config variable loaded by load_config.
  upsert_record A "$host" "$SERVER_PUBLIC_IPV4" "" "$zone"
  if [[ -n "${SERVER_PUBLIC_IPV6:-}" ]]; then
    upsert_record AAAA "$host" "$SERVER_PUBLIC_IPV6" "" "$zone"
  fi
}

zone="$(resolve_zone_id)"
info "Applying Cloudflare DNS records for $target_domain"

add_host_records "$MAIL_HOSTNAME" "$zone"
add_host_records "$WEBMAIL_HOSTNAME" "$zone"
add_host_records "$DAV_HOSTNAME" "$zone"
add_host_records "mta-sts.$target_domain" "$zone"

upsert_record MX "$target_domain" "$MAIL_HOSTNAME" 10 "$zone"
upsert_record TXT "$target_domain" "v=spf1 mx -all" "" "$zone"
upsert_record TXT "_dmarc.$target_domain" "v=DMARC1; p=none; rua=mailto:dmarc@$target_domain; adkim=s; aspf=s" "" "$zone"
upsert_record TXT "_mta-sts.$target_domain" "v=STSv1; id=1" "" "$zone"
upsert_record TXT "_smtp._tls.$target_domain" "v=TLSRPTv1; rua=mailto:postmaster@$target_domain" "" "$zone"

dkim_txt="$DKIM_ROOT/$target_domain/$DKIM_SELECTOR.txt"
if [[ ! -f "$dkim_txt" && "$target_domain" == "$(normalize_domain "$PRIMARY_DOMAIN")" ]]; then
  ensure_dkim_key_for_domain "$target_domain"
fi
if [[ -r "$dkim_txt" ]]; then
  dkim_record="$(format_dkim_dns_record_file "$dkim_txt" "$target_domain")"
  dkim_name="${dkim_record%%. TXT *}"
  dkim_value="${dkim_record#*. TXT }"
  dkim_value="${dkim_value#\"}"
  dkim_value="${dkim_value%\"}"
  upsert_record TXT "$dkim_name" "$dkim_value" "" "$zone"
else
  warn "DKIM record is not generated/readable yet: $dkim_txt"
fi

tlsa_cert_file="${MAILSERVER_TLSA_CERT_FILE:-/etc/letsencrypt/live/$MAIL_HOSTNAME/fullchain.pem}"
if tlsa_record="$(tlsa_record_from_cert_file "$tlsa_cert_file" "$MAIL_HOSTNAME")"; then
  tlsa_name="${tlsa_record%%. TLSA *}"
  tlsa_value="${tlsa_record#*. TLSA }"
  upsert_record TLSA "$tlsa_name" "$tlsa_value" "" "$zone"
fi

info "Cloudflare DNS apply complete. PTR/rDNS still has to be set at the server/IP provider."
