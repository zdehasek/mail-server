#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { usage_line "Usage: sudo mailserver users rm --user user@example.com [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
[[ "${#POSITIONAL[@]}" -eq 1 ]] || { usage; exit 1; }
require_root
load_config

email="${POSITIONAL[0]}"
[[ "$email" == *@* ]] || die "Invalid email address: $email"

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would deactivate mailbox $email"
  exit 0
fi

email_q="$(sql_quote "$email")"
changes="$(psql_mail_scalar -c "WITH updated AS (UPDATE users SET active=false WHERE email='$email_q' AND active=true RETURNING 1) SELECT COUNT(*) FROM updated;")"

if [[ "$changes" -eq 0 ]]; then
  die "Active mailbox not found: $email"
fi

info "Mailbox deactivated: $email"
info "Maildir was left on disk for recovery."
