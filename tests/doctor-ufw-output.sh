#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
doctor="$ROOT_DIR/doctor.sh"

assert_contains() {
  local needle="$1"
  if ! grep -Fq "$needle" "$doctor"; then
    printf 'Expected doctor.sh to contain:\n%s\n' "$needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  local needle="$1"
  if grep -Fq "$needle" "$doctor"; then
    printf 'Expected doctor.sh not to contain:\n%s\n' "$needle" >&2
    exit 1
  fi
}

assert_contains "run_ufw_quiet"
assert_contains "UFW allows 25/tcp SMTP"
assert_contains "UFW allows 587/tcp SMTP submission"
assert_contains "UFW is enabled"
assert_not_contains "run ufw allow 25/tcp"
assert_not_contains "run ufw --force enable"

printf 'doctor UFW output ok\n'
