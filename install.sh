#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"

parse_common_args "$@"
require_root
load_config

if [[ "$DRY_RUN" != "true" ]]; then
  confirm "Install and configure the mail server on this host?" || die "Cancelled."
fi

phases=(
  00-preflight
  10-packages
  20-system
  30-certs
  40-database
  50-dovecot
  60-postfix
  70-dkim-dmarc-rspamd
  80-nginx-roundcube
  90-radicale
  92-primary-mailbox
  95-security
  99-verify
)

for phase in "${phases[@]}"; do
  info "Running phase $phase"
  # shellcheck source=/dev/null
  source "$ROOT_DIR/phases/$phase.sh"
done

info "Install flow complete. Run mailserver print-dns --config $CONFIG_FILE and publish DNS records."
