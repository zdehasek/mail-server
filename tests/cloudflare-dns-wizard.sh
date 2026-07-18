#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mailserver_source="$(< "$ROOT_DIR/mailserver.sh")"

assert_contains() {
  local needle="$1"
  if [[ "$mailserver_source" != *"$needle"* ]]; then
    printf 'Expected mailserver.sh to contain:\n%s\n' "$needle" >&2
    exit 1
  fi
}

assert_contains 'Apply these DNS records through Cloudflare now?'
assert_contains 'Cloudflare API token (Zone:DNS Write, Zone:Zone Read; not stored)'
# shellcheck disable=SC2016
assert_contains 'CLOUDFLARE_API_TOKEN_FILE="$token_file"'
assert_contains 'scripts/apply-cloudflare-dns.sh'

# shellcheck disable=SC2016
if [[ "$mailserver_source" == *'CLOUDFLARE_API_TOKEN="$token"'* ]]; then
  printf 'Wizard should not pass the Cloudflare token directly in the logged command\n' >&2
  exit 1
fi

printf 'cloudflare DNS wizard wiring ok\n'
