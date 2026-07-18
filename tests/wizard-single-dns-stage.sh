#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mailserver_source="$(< "$ROOT_DIR/mailserver.sh")"

count="$(grep -Fc 'wait_for_dns_stage "$config"' "$ROOT_DIR/mailserver.sh")"
if [[ "$count" -ne 1 ]]; then
  printf 'Expected guided init to call wait_for_dns_stage once, got %s\n' "$count" >&2
  exit 1
fi

if [[ "$mailserver_source" == *"final DNS"* || "$mailserver_source" == *"DKIM and final DNS"* ]]; then
  printf 'Guided init should not describe a second final DNS step\n' >&2
  exit 1
fi

printf 'wizard single DNS stage ok\n'
