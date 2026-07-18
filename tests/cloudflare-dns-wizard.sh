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

assert_contains 'Do you have a Cloudflare API token to apply DNS automatically?'
assert_contains 'scripts/apply-cloudflare-dns.sh'

if [[ "$mailserver_source" == *'CLOUDFLARE_API_TOKEN'* || "$mailserver_source" == *'CLOUDFLARE_API_TOKEN_FILE'* || "$mailserver_source" == *'CLOUDFLARE_ZONE_ID'* ]]; then
  printf 'Wizard should not expose alternate Cloudflare token or zone paths\n' >&2
  exit 1
fi

printf 'cloudflare DNS wizard wiring ok\n'
