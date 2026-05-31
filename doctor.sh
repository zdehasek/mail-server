#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/preflight.sh
source "$ROOT_DIR/lib/preflight.sh"

parse_common_args "$@"
load_config
run_preflight

info "Doctor checks completed. Warnings above may still require manual DNS/provider action."
