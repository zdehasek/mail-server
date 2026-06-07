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
  info "Would change password for $email"
  exit 0
fi

read -r -s -p "New password for $email: " password
printf '\n'
read -r -s -p "Confirm password: " password2
printf '\n'
[[ "$password" == "$password2" ]] || die "Passwords do not match."

hash="$(doveadm pw -s SHA512-CRYPT -p "$password")"
email_q="$(sql_quote "$email")"
hash_q="$(sql_quote "$hash")"
sqlite3 "$MAIL_DB_PATH" "UPDATE users SET password_hash='$hash_q' WHERE email='$email_q' AND active=1;"
htpasswd -B -b /etc/radicale/users "$email" "$password" >/dev/null
chown radicale:radicale /etc/radicale/users
chmod 0640 /etc/radicale/users
provision_radicale_calendar "$email" "$password"
info "Password changed for $email"
