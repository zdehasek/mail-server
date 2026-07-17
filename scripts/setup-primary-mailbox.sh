#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

parse_config_only_args "$@" || {
  usage_line "Usage: sudo mailserver setup-primary-mailbox [--config PATH] [--dry-run]"
  exit 0
}
require_root
load_config

if [[ -z "${PRIMARY_MAILBOX:-}" ]]; then
  info "PRIMARY_MAILBOX is empty; skipping primary mailbox setup."
  exit 0
fi

email="$PRIMARY_MAILBOX"
full_name="${PRIMARY_MAILBOX_FULL_NAME:-$email}"
domain="${email#*@}"
localpart="${email%@*}"
[[ "$email" == *@* && -n "$domain" && -n "$localpart" ]] || die "Invalid PRIMARY_MAILBOX: $email"
IFS=' ' read -r -a primary_alias_addresses <<< "$PRIMARY_ALIAS_ADDRESSES"

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would create primary mailbox $email"
  for alias_addr in "${primary_alias_addresses[@]}"; do
    [[ -n "$alias_addr" ]] || continue
    [[ "$alias_addr" == "$email" ]] && continue
    info "Would add primary alias $alias_addr -> $email"
  done
  exit 0
fi

dkim_domain_args=("$domain")
for alias_addr in "${primary_alias_addresses[@]}"; do
  [[ -n "$alias_addr" ]] || continue
  [[ "$alias_addr" == *@* ]] || die "Invalid primary alias address: $alias_addr"
  dkim_domain_args+=("${alias_addr#*@}")
done
refresh_opendkim_domain_maps "${dkim_domain_args[@]}"
reload_or_restart opendkim

domain_q="$(sql_quote "$domain")"
email_q="$(sql_quote "$email")"
local_q="$(sql_quote "$localpart")"
name_q="$(sql_quote "$full_name")"
home_q="$(sql_quote "$VMAIL_ROOT/$domain/$localpart")"
maildir_q="$(sql_quote "$domain/$localpart/Maildir/")"
mailbox_exists="$(psql_mail_scalar -c "SELECT COUNT(*) FROM users WHERE email='$email_q';")"

password="${PRIMARY_MAILBOX_PASSWORD:-}"
update_password=false
if [[ -n "$password" ]]; then
  update_password=true
  install -d -m 0700 "$(dirname "$PRIMARY_MAILBOX_PASSWORD_FILE")"
  if [[ ! -f "$PRIMARY_MAILBOX_PASSWORD_FILE" ]]; then
    printf '%s\n' "$password" > "$PRIMARY_MAILBOX_PASSWORD_FILE"
    chmod 0600 "$PRIMARY_MAILBOX_PASSWORD_FILE"
  fi
elif [[ "$mailbox_exists" -eq 0 ]]; then
  update_password=true
  if [[ -f "$PRIMARY_MAILBOX_PASSWORD_FILE" ]]; then
    password="$(<"$PRIMARY_MAILBOX_PASSWORD_FILE")"
  else
    password="$(openssl rand -base64 24)"
    install -d -m 0700 "$(dirname "$PRIMARY_MAILBOX_PASSWORD_FILE")"
    printf '%s\n' "$password" > "$PRIMARY_MAILBOX_PASSWORD_FILE"
    chmod 0600 "$PRIMARY_MAILBOX_PASSWORD_FILE"
  fi
else
  info "Primary mailbox $email already exists; preserving existing password hash."
  if [[ -f "$PRIMARY_MAILBOX_PASSWORD_FILE" ]]; then
    existing_hash="$(psql_mail_scalar -c "SELECT password_hash FROM users WHERE email='$email_q' AND active=true;")"
    if [[ -n "$existing_hash" ]]; then
      if ! doveadm pw -t "$existing_hash" -p "$(<"$PRIMARY_MAILBOX_PASSWORD_FILE")" >/dev/null 2>&1; then
        die "Primary mailbox password file does not match the existing mailbox password: $PRIMARY_MAILBOX_PASSWORD_FILE"
      fi
    fi
  fi
fi

psql_mail <<SQL
INSERT INTO domains(name, active) VALUES('$domain_q', true)
ON CONFLICT(name) DO UPDATE SET active=true;
SQL

if [[ "$update_password" == "true" ]]; then
  hash="$(doveadm pw -s SHA512-CRYPT -p "$password")"
  hash_q="$(sql_quote "$hash")"
  psql_mail <<SQL
INSERT INTO users(domain_id, email, username, full_name, password_hash, home, maildir, active)
VALUES((SELECT id FROM domains WHERE name='$domain_q'), '$email_q', '$local_q', '$name_q', '$hash_q', '$home_q', '$maildir_q', true)
ON CONFLICT(email) DO UPDATE SET
  password_hash=excluded.password_hash,
  username=excluded.username,
  full_name=excluded.full_name,
  home=excluded.home,
  maildir=excluded.maildir,
  active=true;
SQL
else
  psql_mail <<SQL
UPDATE users
SET
  domain_id=(SELECT id FROM domains WHERE name='$domain_q'),
  username='$local_q',
  full_name='$name_q',
  home='$home_q',
  maildir='$maildir_q',
  active=true
WHERE email='$email_q';
SQL
fi

install -d -o vmail -g vmail -m 0700 "$VMAIL_ROOT/$domain/$localpart/Maildir"

for alias_addr in "${primary_alias_addresses[@]}"; do
  [[ -n "$alias_addr" ]] || continue
  [[ "$alias_addr" == "$email" ]] && continue
  [[ "$alias_addr" == *@* ]] || die "Invalid primary alias address: $alias_addr"
  alias_domain="${alias_addr#*@}"
  alias_domain_q="$(sql_quote "$alias_domain")"
  alias_q="$(sql_quote "$alias_addr")"
  dest_q="$(sql_quote "$email")"
  psql_mail <<SQL
INSERT INTO domains(name, active) VALUES('$alias_domain_q', true)
ON CONFLICT(name) DO UPDATE SET active=true;
INSERT INTO aliases(domain_id, source, destination, active)
VALUES((SELECT id FROM domains WHERE name='$alias_domain_q'), '$alias_q', '$dest_q', true)
ON CONFLICT(source, destination) DO UPDATE SET active=true;
SQL
  info "Alias ready: $alias_addr -> $email"
done

info "Primary mailbox ready: $email"
info "Primary mailbox password file: $PRIMARY_MAILBOX_PASSWORD_FILE"
