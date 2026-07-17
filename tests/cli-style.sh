#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export NO_COLOR=1

help_output="$("$ROOT_DIR/mailserver.sh" --help)"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected output to contain:\n%s\n\nActual output:\n%s\n' "$needle" "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'Expected output not to contain:\n%s\n\nActual output:\n%s\n' "$needle" "$haystack" >&2
    exit 1
  fi
}

assert_contains "$help_output" "users ls"
assert_contains "$help_output" "domains add --domain example.com"
assert_contains "$help_output" "aliases set --source postmaster@example.com --dest user@example.com"
assert_not_contains "$help_output" "list-users"
assert_not_contains "$help_output" "add-user"
assert_not_contains "$help_output" "remove-domain"
assert_not_contains "$help_output" "client-config"
assert_not_contains "$help_output" "Alias for"

assert_rejected_with() {
  local expected="$1"
  shift
  local output status

  set +e
  output="$("$ROOT_DIR/mailserver.sh" "$@" 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'Expected command to fail: %s\nOutput:\n%s\n' "$*" "$output" >&2
    exit 1
  fi
  assert_contains "$output" "$expected"
}

assert_rejected_with "Use: mailserver users ls" list-users
assert_rejected_with "Use: mailserver users add --user user@example.com" add-user
assert_rejected_with "Use: mailserver domains rm --domain example.com" remove-domain
assert_rejected_with "Use: mailserver client-info" client-config
assert_rejected_with "Use: mailserver doctor" check
assert_rejected_with "Unknown users action: list. Use: ls, add, rm, or passwd." users list

printf 'CLI public style ok\n'
