#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo $0 [--config ./mail.env] user@example.com [Full Name]"; }
parse_config_only_args "$@" || { usage; exit 0; }
[[ "${#POSITIONAL[@]}" -ge 1 ]] || { usage; exit 1; }
require_root
load_config

email="${POSITIONAL[0]}"
full_name="${POSITIONAL[1]:-$email}"
domain="${email#*@}"
localpart="${email%@*}"
[[ "$email" == *@* && -n "$domain" && -n "$localpart" ]] || die "Invalid email address: $email"

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would create mailbox $email"
  exit 0
fi

read -r -s -p "Password for $email: " password
printf '\n'
read -r -s -p "Confirm password: " password2
printf '\n'
[[ "$password" == "$password2" ]] || die "Passwords do not match."

hash="$(doveadm pw -s SHA512-CRYPT -p "$password")"
domain_q="$(sql_quote "$domain")"
email_q="$(sql_quote "$email")"
local_q="$(sql_quote "$localpart")"
name_q="$(sql_quote "$full_name")"
hash_q="$(sql_quote "$hash")"
home_q="$(sql_quote "$VMAIL_ROOT/$domain/$localpart")"
maildir_q="$(sql_quote "$domain/$localpart/Maildir/")"

sqlite3 "$MAIL_DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
INSERT OR IGNORE INTO domains(name, active) VALUES('$domain_q', 1);
INSERT INTO users(domain_id, email, username, full_name, password_hash, home, maildir, active)
VALUES((SELECT id FROM domains WHERE name='$domain_q'), '$email_q', '$local_q', '$name_q', '$hash_q', '$home_q', '$maildir_q', 1)
ON CONFLICT(email) DO UPDATE SET password_hash=excluded.password_hash, full_name=excluded.full_name, active=1;
SQL

install -d -o vmail -g vmail -m 0700 "$VMAIL_ROOT/$domain/$localpart/Maildir"
htpasswd -B -b /etc/radicale/users "$email" "$password" >/dev/null
chown radicale:radicale /etc/radicale/users
chmod 0640 /etc/radicale/users
provision_radicale_calendar "$email" "$password"
info "Mailbox ready: $email"
