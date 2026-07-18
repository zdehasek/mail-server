#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

config="$tmp_dir/config.env"
dkim_root="$tmp_dir/dkim"
dkim_dir="$dkim_root/example.com"
mkdir -p "$dkim_dir"
cat > "$dkim_dir/default.txt" <<'DKIM'
default._domainkey IN TXT ( "v=DKIM1; k=rsa; " "p=ABC123" ) ; ----- DKIM key default for example.com
DKIM

cat > "$config" <<CONFIG
MAIL_HOSTNAME=mail.example.com
PRIMARY_DOMAIN=example.com
SECONDARY_DOMAINS=
ADMIN_EMAIL=admin@example.com
WEBMAIL_HOSTNAME=mail.example.com
DAV_HOSTNAME=dav.example.com
SERVER_PUBLIC_IPV4=203.0.113.10
SERVER_PUBLIC_IPV6=2001:db8::10
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

output="$("$ROOT_DIR/scripts/apply-cloudflare-dns.sh" --config "$config" --dry-run)"
help_output="$("$ROOT_DIR/scripts/apply-cloudflare-dns.sh" --help)"
script_source="$(< "$ROOT_DIR/scripts/apply-cloudflare-dns.sh")"
packages_source="$(< "$ROOT_DIR/phases/10-packages.sh")"

assert_contains() {
  local needle="$1"
  if [[ "$output" != *"$needle"* ]]; then
    printf 'Expected output to contain:\n%s\n\nActual output:\n%s\n' "$needle" "$output" >&2
    exit 1
  fi
}

assert_contains "Would upsert Cloudflare DNS: mail.example.com. A 203.0.113.10"
assert_contains "Would upsert Cloudflare DNS: mail.example.com. AAAA 2001:db8::10"
assert_contains "Would upsert Cloudflare DNS: example.com. MX 10 mail.example.com."
assert_contains "Would upsert Cloudflare DNS: example.com. TXT v=spf1 mx -all"
assert_contains "Would upsert Cloudflare DNS: _dmarc.example.com. TXT v=DMARC1; p=none; rua=mailto:dmarc@example.com; adkim=s; aspf=s"
assert_contains "Would upsert Cloudflare DNS: default._domainkey.example.com. TXT v=DKIM1; k=rsa; p=ABC123"
assert_contains "PTR/rDNS still has to be set at the server/IP provider"

if [[ "$help_output" == *"--token"* || "$help_output" == *"--zone-id"* ]]; then
  printf 'Cloudflare DNS help should not expose token or zone-id options:\n%s\n' "$help_output" >&2
  exit 1
fi

if "$ROOT_DIR/scripts/apply-cloudflare-dns.sh" --config "$config" --dry-run --token secret >/dev/null 2>&1; then
  printf 'Cloudflare DNS command should reject --token\n' >&2
  exit 1
fi

if [[ "$script_source" == *"python"* ]]; then
  printf 'Cloudflare DNS command should not depend on Python\n' >&2
  exit 1
fi

if [[ "$packages_source" != *" jq "* ]]; then
  printf 'jq should be installed with support packages\n' >&2
  exit 1
fi

printf 'cloudflare DNS dry-run output ok\n'
