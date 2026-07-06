#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() {
  echo "Usage: sudo mailserver e2e-delivery [--user user@example.com] [--password-file PATH] [--no-cleanup] [--config PATH]"
}

parse_config_only_args "$@" || { usage; exit 0; }
require_root
load_config

account="${PRIMARY_MAILBOX:-}"
password_file="${PRIMARY_MAILBOX_PASSWORD_FILE:-}"
cleanup="true"

while [[ "${#POSITIONAL[@]}" -gt 0 ]]; do
  case "${POSITIONAL[0]}" in
    --user)
      account="${POSITIONAL[1]:-}"
      [[ -n "$account" ]] || die "Missing value for --user."
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    --password-file)
      password_file="${POSITIONAL[1]:-}"
      [[ -n "$password_file" ]] || die "Missing value for --password-file."
      POSITIONAL=("${POSITIONAL[@]:2}")
      ;;
    --no-cleanup)
      cleanup="false"
      POSITIONAL=("${POSITIONAL[@]:1}")
      ;;
    *)
      die "Unknown e2e-delivery option: ${POSITIONAL[0]}"
      ;;
  esac
done

[[ -n "$account" && "$account" == *@* ]] || die "Missing or invalid test account. Use --user user@example.com."
[[ -f "$password_file" ]] || die "Password file not found: $password_file"
command -v doveadm >/dev/null 2>&1 || die "doveadm is required."
[[ -x /usr/sbin/sendmail ]] || die "/usr/sbin/sendmail is required."

subject="mailserver-e2e-$(date -u +%Y%m%dT%H%M%SZ)-$$"
message_id="<${subject}@${PRIMARY_DOMAIN}>"

info "Injecting local SMTP test message to $account"
/usr/sbin/sendmail -i "$account" <<MAIL
From: $account
To: $account
Subject: $subject
Message-ID: $message_id
Date: $(LC_ALL=C date -Ru)

Local end-to-end delivery test from mailserver e2e-delivery.
MAIL

uid=""
for _ in {1..20}; do
  uid="$(doveadm search -u "$account" mailbox INBOX HEADER Message-ID "$message_id" 2>/dev/null | awk '{print $2}' | tail -n 1 || true)"
  [[ -n "$uid" ]] && break
  sleep 1
done

[[ -n "$uid" ]] || die "Message was not found in $account INBOX via Dovecot."
info "Dovecot IMAP storage OK: UID $uid"

password="$(<"$password_file")"
dav_url="https://$WEBMAIL_HOSTNAME/SOGo/dav/$account/"
status="$(curl -fsS -o /dev/null -w '%{http_code}' -u "$account:$password" -X PROPFIND -H 'Depth: 0' "$dav_url" || true)"
[[ "$status" == "207" ]] || die "SOGo DAV PROPFIND returned HTTP ${status:-<none>}, expected 207: $dav_url"
info "SOGo DAV OK: $dav_url returned 207"

if [[ "$cleanup" == "true" ]]; then
  doveadm expunge -u "$account" mailbox INBOX HEADER Message-ID "$message_id" || true
  info "Cleaned up test message $message_id"
else
  info "Leaving test message in INBOX because --no-cleanup was set."
fi

info "End-to-end delivery test passed."
