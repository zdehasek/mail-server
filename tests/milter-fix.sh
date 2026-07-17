#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected output to contain:\n%s\n\nActual output:\n%s\n' "$needle" "$haystack" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    printf 'Expected %s to contain:\n%s\n' "$file" "$needle" >&2
    exit 1
  fi
}

assert_file_contains "$ROOT_DIR/phases/70-dkim-dmarc-rspamd.sh" "configure_milter_tcp_sockets"
assert_file_contains "$ROOT_DIR/phases/70-dkim-dmarc-rspamd.sh" "run systemctl restart opendkim"
assert_file_contains "$ROOT_DIR/phases/70-dkim-dmarc-rspamd.sh" "run systemctl restart opendmarc"
assert_file_contains "$ROOT_DIR/doctor.sh" "apply_milter_fixes"
assert_file_contains "$ROOT_DIR/doctor.sh" "configure_milter_tcp_sockets"
assert_file_contains "$ROOT_DIR/doctor.sh" 'run systemctl restart "$service"'
assert_file_contains "$ROOT_DIR/doctor.sh" "OpenDKIM milter is still not listening on 127.0.0.1:8891 after restart"
assert_file_contains "$ROOT_DIR/doctor.sh" "OpenDMARC milter is still not listening on 127.0.0.1:8893 after restart"
assert_file_contains "$ROOT_DIR/lib/common.sh" "SOCKET=inet:8891@127.0.0.1"
assert_file_contains "$ROOT_DIR/lib/common.sh" "SOCKET=inet:8893@127.0.0.1"

service_state_source="$(< "$ROOT_DIR/scripts/service-state.sh")"
assert_contains "$service_state_source" 'check_port 587 "SMTP submission" "master|postfix|smtpd"'
assert_contains "$service_state_source" "OpenDKIM milter; repair with: sudo mailserver doctor --fix"
assert_contains "$service_state_source" "OpenDMARC milter; repair with: sudo mailserver doctor --fix"

printf 'milter socket repair wiring ok\n'
