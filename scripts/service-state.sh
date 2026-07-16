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
  local expected_regex="$3"
  local listener

  if port_is_listening "$port"; then
    listener="$(port_listener_summary "$port")"
    if port_listener_has_expected "$port" "$expected_regex"; then
      ok_state "port $port listening: $name via $listener"
    else
      fail_state "port $port is occupied by $listener, expected $name ($expected_regex)"
    fi
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
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$url" || true)"
  if [[ "$code" == "$expected" ]]; then
    ok_state "$url returns HTTP $code"
  elif [[ -z "$code" || "$code" == "000" ]]; then
    fail_state "$url was not reachable with a valid TLS certificate"
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
    curl -sSI --max-time 15 "$url" \
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

ui_heading "Service state for $PRIMARY_DOMAIN"
ui_blank

services=(postgresql postfix dovecot nginx memcached sogo opendkim opendmarc fail2ban)
[[ "${ENABLE_RSPAMD:-true}" == "true" ]] && services+=(rspamd)
for service in "${services[@]}"; do
  check_service "$service"
done

check_port 25 "SMTP" "master|postfix"
check_port 80 "HTTP / Let's Encrypt" "nginx"
check_port 443 "HTTPS" "nginx"
check_port 587 "SMTP submission" "master|postfix"
check_port 993 "IMAPS" "dovecot"
check_port 8891 "OpenDKIM milter" "opendkim"
check_port 8893 "OpenDMARC milter" "opendmarc"
check_port 20000 "SOGo" "sogod"
[[ "${ENABLE_RSPAMD:-true}" == "true" ]] && check_port 11332 "Rspamd milter" "rspamd"

ui_blank
ui_subheading "External IPv4 reachability"
check_external_port 25 "SMTP"
check_external_port 80 "HTTP / Let's Encrypt"
check_external_port 443 "HTTPS"
check_external_port 587 "SMTP submission"
check_external_port 993 "IMAPS"

check_http "https://$WEBMAIL_HOSTNAME/" "302"
check_http "https://$WEBMAIL_HOSTNAME/SOGo/" "200"
check_css_content_type "https://$WEBMAIL_HOSTNAME/SOGo/WebServerResources/css/theme-default.css" "SOGo theme CSS"
check_javascript_content_type "https://$WEBMAIL_HOSTNAME/SOGo/WebServerResources/js/Common.js" "SOGo Common.js"
check_http "https://$DAV_HOSTNAME/SOGo/dav/" "401"

ui_blank
ui_summary "$failures" "$warnings" "$failures failure(s), $warnings warning(s)"
[[ "$failures" -eq 0 ]]
