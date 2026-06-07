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

check_http "https://$WEBMAIL_HOSTNAME/" "200"
check_http "https://$DAV_HOSTNAME/" "302"
check_css_content_type "https://$WEBMAIL_HOSTNAME/static.php/skins/elastic/styles/styles.min.css" "Roundcube CSS"
check_javascript_content_type "https://$WEBMAIL_HOSTNAME/static.php/program/js/app.min.js" "Roundcube JavaScript"
check_svg_content_type "https://$WEBMAIL_HOSTNAME/static.php/skins/elastic/images/logo.svg" "Roundcube logo"
if [[ "${ENABLE_ROUNDCUBE_CALENDAR:-true}" == "true" ]]; then
  check_css_content_type "https://$WEBMAIL_HOSTNAME/plugins/calendar/skins/elastic/elastic.min.css" "Roundcube calendar CSS"
  check_css_content_type "https://$WEBMAIL_HOSTNAME/static.php/plugins/calendar/skins/elastic/fullcalendar.css" "Roundcube calendar FullCalendar CSS"
  check_css_content_type "https://$WEBMAIL_HOSTNAME/static.php/plugins/calendar/skins/elastic/calendar.css" "Roundcube calendar skin CSS"
  check_css_content_type "https://$WEBMAIL_HOSTNAME/static.php/plugins/libkolab/skins/elastic/libkolab.css" "Roundcube libkolab skin CSS"
  check_css_content_type "https://$WEBMAIL_HOSTNAME/static.php/plugins/libcalendaring/skins/elastic/libcal.css" "Roundcube libcalendaring skin CSS"
  check_javascript_content_type "https://$WEBMAIL_HOSTNAME/plugins/calendar/calendar_base.js" "Roundcube calendar JavaScript"
fi

printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
[[ "$failures" -eq 0 ]]
