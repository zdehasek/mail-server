#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

config="$tmp_dir/config.env"
cert="$tmp_dir/fullchain.pem"
key="$tmp_dir/key.pem"
dkim_root="$tmp_dir/dkim"

cat > "$config" <<CONFIG
MAIL_HOSTNAME=mail.example.com
PRIMARY_DOMAIN=example.com
SECONDARY_DOMAINS=
ADMIN_EMAIL=admin@example.com
WEBMAIL_HOSTNAME=mail.example.com
DAV_HOSTNAME=dav.example.com
SERVER_PUBLIC_IPV4=203.0.113.10
SERVER_PUBLIC_IPV6=
TIMEZONE=UTC
VMAIL_UID=5000
VMAIL_GID=5000
VMAIL_ROOT=/var/vmail
MAIL_DB_NAME=mailserver
MAIL_DB_USER=mailserver
MAIL_DB_HOST=127.0.0.1
MAIL_DB_PASSWORD_FILE=/tmp/mailserver-password
MAIL_DB_PATH=/tmp/mail.sqlite
LETSENCRYPT_STAGING=false
ENABLE_UFW=true
UFW_RESET_RULES=true
ENABLE_FAIL2BAN=true
ENABLE_SSH_HARDENING=true
ENABLE_RSPAMD=true
ENABLE_CLAMAV=false
SSH_PORT=22
SSH_ALLOW_USERS=
BACKUP_DIR=/tmp/mailserver-backup
BACKUP_RETENTION_DAYS=14
BACKUP_CRON_SCHEDULE="17 3 * * *"
POSTMASTER_ADDRESS=postmaster@example.com
ABUSE_ADDRESS=abuse@example.com
DKIM_SELECTOR=default
DKIM_ROOT=$dkim_root
PRIMARY_MAILBOX=admin@example.com
PRIMARY_MAILBOX_FULL_NAME="Mail Admin"
PRIMARY_MAILBOX_PASSWORD=
PRIMARY_MAILBOX_PASSWORD_FILE=/tmp/primary-mailbox-password
PRIMARY_ALIAS_ADDRESSES="postmaster@example.com abuse@example.com dmarc@example.com admin@example.com"
CONFIG

openssl req -x509 -newkey rsa:2048 -keyout "$key" -out "$cert" -days 1 -nodes -subj /CN=mail.example.com >/dev/null 2>&1

output="$(MAILSERVER_TLSA_CERT_FILE="$cert" "$ROOT_DIR/scripts/print-dns.sh" --config "$config" --skip-dkim)"

assert_contains() {
  local needle="$1"
  if [[ "$output" != *"$needle"* ]]; then
    printf 'Expected output to contain:\n%s\n\nActual output:\n%s\n' "$needle" "$output" >&2
    exit 1
  fi
}

assert_contains "Optional TLS policy DNS records:"
assert_contains "mta-sts.example.com. A 203.0.113.10"
assert_contains '_mta-sts.example.com. TXT "v=STSv1; id=1"'
assert_contains '_smtp._tls.example.com. TXT "v=TLSRPTv1; rua=mailto:postmaster@example.com"'
assert_contains "_25._tcp.mail.example.com. TLSA 3 1 1 "

printf 'print-dns TLS policy output ok\n'
