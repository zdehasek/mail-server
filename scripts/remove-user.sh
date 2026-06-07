#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo $0 [--config ./mail.env] user@example.com"; }
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
changes="$(sqlite3 "$MAIL_DB_PATH" <<SQL
UPDATE users SET active=0 WHERE email='$email_q' AND active=1;
SELECT changes();
SQL
)"

if [[ "$changes" -eq 0 ]]; then
  die "Active mailbox not found: $email"
fi

if [[ -f /etc/radicale/users ]]; then
  htpasswd -D /etc/radicale/users "$email" >/dev/null 2>&1 || true
  chown radicale:radicale /etc/radicale/users
  chmod 0640 /etc/radicale/users
fi

info "Mailbox deactivated: $email"
info "Maildir was left on disk for recovery."
