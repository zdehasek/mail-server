#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$ROOT_DIR/scripts/config-drift.sh"

if grep -Fq 'warn_state "config-drift is scoped' "$script"; then
  printf 'config-drift scope disclaimer must not increment warning count\n' >&2
  exit 1
fi

if ! grep -Fq 'info "config-drift is scoped' "$script"; then
  printf 'Expected config-drift scope disclaimer to remain as info\n' >&2
  exit 1
fi

printf 'config-drift scope disclaimer ok\n'
