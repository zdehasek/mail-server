#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
remove_source="$(< "$ROOT_DIR/scripts/remove.sh")"
system_phase_source="$(< "$ROOT_DIR/phases/20-system.sh")"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected source to contain:\n%s\n' "$needle" >&2
    exit 1
  fi
}

assert_contains "$remove_source" 'This will remove the recurring backup cron: /etc/cron.d/mailserver-backup'
assert_contains "$system_phase_source" 'run_rm /etc/cron.d/mailserver-backup'
assert_contains "$system_phase_source" 'run_rm /var/log/mailserver-backup.log'

printf 'remove purge cron cleanup wiring ok\n'
