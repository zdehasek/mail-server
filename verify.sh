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

services=(postgresql postfix dovecot nginx memcached sogo opendkim opendmarc)
[[ "${ENABLE_RSPAMD:-true}" == "true" ]] && services+=(rspamd)

for service in "${services[@]}"; do
  systemctl is-active --quiet "$service" || die "Service is not active: $service"
  info "Service active: $service"
done

check_web_asset_content_type() {
  local url="$1"
  local expected_prefixes="$2"
  local content_type expected_prefix
  content_type="$(
    curl -sSI --max-time 15 "$url" \
      | awk 'tolower($0) ~ /^content-type:/ {print $2; exit}' \
      | tr -d '\r'
  )" || true
  IFS='|' read -r -a expected_prefix_list <<< "$expected_prefixes"
  for expected_prefix in "${expected_prefix_list[@]}"; do
    if [[ "$content_type" == "$expected_prefix"* ]]; then
      info "Web asset OK: $url returns $content_type"
      return
    fi
  done
  die "$url returned content-type ${content_type:-<none>}, expected $expected_prefixes"
}

check_web_asset_content_type "https://$WEBMAIL_HOSTNAME/SOGo/WebServerResources/css/theme-default.css" "text/css"
check_web_asset_content_type "https://$WEBMAIL_HOSTNAME/SOGo/WebServerResources/js/Common.js" "text/javascript|application/javascript"

info "Verification completed. Run mailserver check and mailserver e2e-delivery for external/TLS and delivery coverage."
