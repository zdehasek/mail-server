#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
preflight="$ROOT_DIR/lib/preflight.sh"
doctor="$ROOT_DIR/doctor.sh"
mailserver="$ROOT_DIR/mailserver.sh"

assert_contains_file() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    printf 'Expected %s to contain:\n%s\n' "$file" "$needle" >&2
    exit 1
  fi
}

assert_contains_file "$preflight" '"25:SMTP:master|postfix|smtpd"'
assert_contains_file "$preflight" '"587:SMTP submission:master|postfix|smtpd"'
assert_contains_file "$preflight" 'MAILSERVER_SKIP_PREFLIGHT_DNS'
assert_contains_file "$preflight" 'MAILSERVER_SKIP_PREFLIGHT_FIREWALL_NOTICE'
assert_contains_file "$mailserver" 'MAILSERVER_SKIP_PREFLIGHT_DNS=true'
assert_contains_file "$doctor" 'MAILSERVER_SKIP_PREFLIGHT_FIREWALL_NOTICE=true'

printf 'preflight output ok\n'
