#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

parse_config_only_args "$@" || true
load_config

failures=0
warnings=0
expiry_warn_seconds=$((30 * 24 * 60 * 60))

ok() { printf 'OK    %s\n' "$*"; }
warn_state() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
fail_state() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }

fetch_cert() {
  local host="$1"
  local port="$2"
  local mode="${3:-}"
  local args=(-connect "$host:$port" -servername "$host" -verify_return_error -showcerts)
  [[ "$mode" == "smtp" ]] && args=(-starttls smtp "${args[@]}")
  timeout 20 openssl s_client "${args[@]}" </dev/null 2>/dev/null |
    sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' |
    sed -n '1,/-----END CERTIFICATE-----/p'
}

check_cert() {
  local label="$1"
  local host="$2"
  local port="$3"
  local mode="${4:-}"
  local cert subject expires

  cert="$(fetch_cert "$host" "$port" "$mode")"
  if [[ -z "$cert" ]]; then
    fail_state "$label: no certificate from $host:$port"
    return 0
  fi

  if openssl x509 -noout -checkhost "$host" <<< "$cert" >/dev/null 2>&1; then
    ok "$label: certificate matches $host"
  else
    fail_state "$label: certificate does not match $host"
  fi

  if openssl x509 -noout -checkend 0 <<< "$cert" >/dev/null 2>&1; then
    expires="$(openssl x509 -noout -enddate <<< "$cert" | sed 's/^notAfter=//')"
    ok "$label: certificate is not expired; expires $expires"
  else
    fail_state "$label: certificate is expired"
  fi

  if openssl x509 -noout -checkend "$expiry_warn_seconds" <<< "$cert" >/dev/null 2>&1; then
    ok "$label: certificate is valid for at least 30 days"
  else
    warn_state "$label: certificate expires in less than 30 days"
  fi

  subject="$(openssl x509 -noout -subject <<< "$cert" | sed 's/^subject=//')"
  ok "$label: subject $subject"
}

printf 'SSL/TLS state for %s\n\n' "$PRIMARY_DOMAIN"

declare -A https_hosts=()
https_hosts["$MAIL_HOSTNAME"]=1
https_hosts["$WEBMAIL_HOSTNAME"]=1
https_hosts["$DAV_HOSTNAME"]=1

for host in "${!https_hosts[@]}"; do
  check_cert "HTTPS $host" "$host" 443
done

check_cert "IMAPS $MAIL_HOSTNAME" "$MAIL_HOSTNAME" 993
check_cert "SMTP submission $MAIL_HOSTNAME" "$MAIL_HOSTNAME" 587 smtp

printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
[[ "$failures" -eq 0 ]]
