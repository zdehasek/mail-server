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

printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
[[ "$failures" -eq 0 ]]
