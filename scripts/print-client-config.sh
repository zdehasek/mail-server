#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: mailserver client-info [--user user@example.com] [--config PATH]"; }

account=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      # load_config reads CONFIG_FILE from the sourced common library.
      # shellcheck disable=SC2034
      CONFIG_FILE="$2"
      shift 2
      ;;
    --user)
      account="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

load_config

account="${account:-$PRIMARY_MAILBOX}"
account="${account:-user@$PRIMARY_DOMAIN}"
calendar_name="${RADICALE_DEFAULT_CALENDAR_NAME:-default}"
caldav_base="${RADICALE_CALDAV_BASE_URL%/}"
caldav_account_url="$caldav_base/$account/"
caldav_calendar_url="$caldav_account_url$calendar_name/"

cat <<CONFIG
Client configuration for $account

Email
  Address: $account
  Username: $account
  Password: mailbox password

Incoming mail (IMAP)
  Server: $MAIL_HOSTNAME
  Port: 993
  Security: SSL/TLS
  Authentication: Normal password

Outgoing mail (SMTP)
  Server: $MAIL_HOSTNAME
  Port: 587
  Security: STARTTLS
  Authentication: Normal password
  Username: $account

Apple Mail
  Add Account -> Other Mail Account
  Email Address: $account
  User Name: $account
  Incoming Mail Server: $MAIL_HOSTNAME
  Outgoing Mail Server: $MAIL_HOSTNAME

Thunderbird Mail
  Configure manually
  Incoming: IMAP, $MAIL_HOSTNAME, 993, SSL/TLS, Normal password
  Outgoing: SMTP, $MAIL_HOSTNAME, 587, STARTTLS, Normal password
  Username: $account

Calendar (CalDAV)
  Username: $account
  Password: mailbox password
  Account URL: $caldav_account_url
  Calendar URL: $caldav_calendar_url

Apple Calendar
  Add Account -> Other CalDAV Account -> Manual
  Server Address: $DAV_HOSTNAME
  User Name: $account
  Advanced Account URL: $caldav_account_url

Thunderbird Calendar
  New Calendar -> On the Network -> CalDAV
  Username: $account
  Location: $caldav_calendar_url

Webmail
  URL: https://$WEBMAIL_HOSTNAME/
CONFIG

if [[ "$account" == "$PRIMARY_MAILBOX" && -n "${PRIMARY_MAILBOX_PASSWORD_FILE:-}" ]]; then
  cat <<CONFIG

Primary mailbox password file on the server:
  $PRIMARY_MAILBOX_PASSWORD_FILE
CONFIG
fi
