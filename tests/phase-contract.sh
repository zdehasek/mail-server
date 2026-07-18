#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for phase in "$ROOT_DIR"/phases/*.sh; do
  # shellcheck source=/dev/null
  source "$phase"
  declare -F up >/dev/null || {
    printf 'Missing up() in %s\n' "${phase#"$ROOT_DIR"/}" >&2
    exit 1
  }
  declare -F down >/dev/null || {
    printf 'Missing down() in %s\n' "${phase#"$ROOT_DIR"/}" >&2
    exit 1
  }
  unset -f up down phase_packages phase_removable_packages
done
