#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export MAILSERVER_SOURCE_ONLY=true
export NO_COLOR=1

# shellcheck source=../mailserver.sh disable=SC1091
source "$ROOT_DIR/mailserver.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="$tmp_dir/wizard.log"

output="$(wizard_run_cmd "Streaming a command" "$log_file" bash -c 'printf "stdout line\n"; printf "stderr line\n" >&2')"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected output to contain:\n%s\n\nActual output:\n%s\n' "$needle" "$haystack" >&2
    exit 1
  fi
}

assert_contains "$output" "stdout line"
assert_contains "$output" "stderr line"

log_output="$(< "$log_file")"
assert_contains "$log_output" "stdout line"
assert_contains "$log_output" "stderr line"

set +e
fail_output="$(wizard_run_cmd "Failing command" "$log_file" bash -c 'printf "before failure\n"; exit 23')"
fail_status=$?
set -e

if [[ "$fail_status" -ne 23 ]]; then
  printf 'Expected failing command status 23, got %s\nOutput:\n%s\n' "$fail_status" "$fail_output" >&2
  exit 1
fi

assert_contains "$fail_output" "before failure"
assert_contains "$fail_output" "Failing command failed. Last log lines:"

printf 'wizard live output streaming ok\n'
