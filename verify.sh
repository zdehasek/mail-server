#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"

parse_common_args "$@"
load_config

checks=(
  "postfix check"
  "doveconf -n >/dev/null"
  "nginx -t"
)

if command -v rspamadm >/dev/null 2>&1; then
  checks+=("rspamadm configtest")
fi

for check in "${checks[@]}"; do
  info "Checking: $check"
  bash -c "$check"
done

services=(postfix dovecot nginx radicale opendkim opendmarc)
[[ "${ENABLE_RSPAMD:-true}" == "true" ]] && services+=(rspamd)

for service in "${services[@]}"; do
  systemctl is-active --quiet "$service" || die "Service is not active: $service"
  info "Service active: $service"
done

if ! systemctl list-units --type=service --state=active 'php*-fpm.service' | grep -q 'php.*-fpm.service'; then
  die "No active PHP-FPM service found."
fi
info "Service active: PHP-FPM"

info "Verification completed. Run external SMTP/TLS and delivery tests from docs/operations.md."
