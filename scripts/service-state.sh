#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

parse_config_only_args "$@" || true
load_config

failures=0
warnings=0

check_service() {
  local service="$1"
  if systemctl is-active --quiet "$service"; then
    ok_state "service active: $service"
  else
    fail_state "service is not active: $service"
  fi
}

check_port() {
  local port="$1"
  local name="$2"
  if ss -tln "( sport = :$port )" | tail -n +2 | grep -q .; then
    ok_state "port $port listening: $name"
  else
    fail_state "port $port is not listening: $name"
  fi
}

json_field() {
  local field="$1"
  sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p; s/.*\"$field\"[[:space:]]*:[[:space:]]*\\([^,}[:space:]]*\\).*/\\1/p" |
    head -n 1
}

check_external_port() {
  local port="$1"
  local name="$2"
  local response ip reachable

  if [[ "${MAILSERVER_SKIP_EXTERNAL_PORT_CHECK:-false}" == "true" ]]; then
    warn_state "external port check skipped for $port: MAILSERVER_SKIP_EXTERNAL_PORT_CHECK=true"
    return
  fi
  if ! command -v curl >/dev/null 2>&1; then
    warn_state "external port check skipped for $port: curl is missing"
    return
  fi

  response="$(
    curl -4 -fsS -A curl --connect-timeout 5 --max-time 20 "https://ifconfig.co/port/$port" 2>/dev/null || true
  )"
  if [[ -z "$response" ]]; then
    warn_state "external port check unavailable for $port: ifconfig.co did not return a result"
    return
  fi

  ip="$(printf '%s\n' "$response" | json_field ip)"
  reachable="$(printf '%s\n' "$response" | json_field reachable)"

  if [[ -n "$ip" && "$ip" != "$SERVER_PUBLIC_IPV4" ]]; then
    warn_state "external port checker saw IPv4 $ip, expected $SERVER_PUBLIC_IPV4"
  fi

  case "$reachable" in
    true)
      ok_state "external port $port reachable: $name"
      ;;
    false)
      fail_state "external port $port is not reachable: $name; check provider firewall/security group and UFW"
      ;;
    *)
      warn_state "external port check returned unexpected response for $port: ${response//$'\n'/ }"
      ;;
  esac
}

check_http() {
  local url="$1"
  local expected="$2"
  local code
  code="$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 15 "$url" || true)"
  if [[ "$code" == "$expected" ]]; then
    ok_state "$url returns HTTP $code"
  else
    warn_state "$url returned HTTP ${code:-<none>}, expected $expected"
  fi
}

check_content_type() {
  local url="$1"
  local expected_prefixes="$2"
  local label="$3"
  local content_type
  content_type="$(
    curl -k -sSI --max-time 15 "$url" \
      | awk 'tolower($0) ~ /^content-type:/ {print $2; exit}' \
      | tr -d '\r'
  )" || true
  local expected_prefix
  IFS='|' read -r -a expected_prefix_list <<< "$expected_prefixes"
  for expected_prefix in "${expected_prefix_list[@]}"; do
    if [[ "$content_type" == "$expected_prefix"* ]]; then
      ok_state "$label returns $content_type"
      return
    fi
  done
  if [[ -n "$content_type" ]]; then
    warn_state "$label returned content-type $content_type, expected $expected_prefixes"
  else
    warn_state "$label returned no content-type, expected $expected_prefixes"
  fi
}

check_javascript_content_type() {
  local url="$1"
  local label="$2"
  check_content_type "$url" "text/javascript|application/javascript" "$label"
}

check_css_content_type() {
  local url="$1"
  local label="$2"
  check_content_type "$url" "text/css" "$label"
}

check_svg_content_type() {
  local url="$1"
  local label="$2"
  check_content_type "$url" "image/svg+xml" "$label"
}

printf 'Service state for %s\n\n' "$PRIMARY_DOMAIN"

services=(postfix dovecot nginx radicale opendkim opendmarc fail2ban)
[[ "${ENABLE_RSPAMD:-true}" == "true" ]] && services+=(rspamd)
for service in "${services[@]}"; do
  check_service "$service"
done

if systemctl is-active --quiet 'php*-fpm.service'; then
  ok_state "service active: PHP-FPM"
else
  fail_state "no active PHP-FPM service found"
fi

check_port 25 "SMTP"
check_port 80 "HTTP / Let's Encrypt"
check_port 443 "HTTPS"
check_port 587 "SMTP submission"
check_port 993 "IMAPS"
check_port 8891 "OpenDKIM milter"
check_port 8893 "OpenDMARC milter"
[[ "${ENABLE_RSPAMD:-true}" == "true" ]] && check_port 11332 "Rspamd milter"

printf '\nExternal IPv4 reachability\n'
check_external_port 25 "SMTP"
check_external_port 80 "HTTP / Let's Encrypt"
check_external_port 443 "HTTPS"
check_external_port 587 "SMTP submission"
check_external_port 993 "IMAPS"

check_http "https://$WEBMAIL_HOSTNAME/" "200"
check_http "https://$DAV_HOSTNAME/" "302"
check_css_content_type "https://$WEBMAIL_HOSTNAME/static.php/skins/elastic/styles/styles.min.css" "Roundcube CSS"
check_javascript_content_type "https://$WEBMAIL_HOSTNAME/static.php/program/js/app.min.js" "Roundcube JavaScript"
check_svg_content_type "https://$WEBMAIL_HOSTNAME/static.php/skins/elastic/images/logo.svg" "Roundcube logo"

printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
[[ "$failures" -eq 0 ]]
