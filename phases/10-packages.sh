#!/usr/bin/env bash

packages=(
  ca-certificates curl gnupg lsb-release dnsutils netcat-openbsd openssl sqlite3 tar cron
  postfix postfix-sqlite postfix-policyd-spf-python
  dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sieve dovecot-managesieved dovecot-sqlite
  nginx certbot apache2-utils radicale
  php-fpm php-cli php-curl php-xml php-mbstring php-zip php-intl php-gd php-sqlite3
  opendkim opendkim-tools opendmarc rspamd fail2ban ufw
)

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would preseed Roundcube package prompts for non-interactive SQLite-managed install"
else
  printf '%s\n' \
    'opendmarc opendmarc/dbconfig-install boolean false' | debconf-set-selections
fi

if [[ "${ENABLE_CLAMAV:-false}" == "true" ]]; then
  packages+=(clamav-daemon clamav-freshclam)
fi

install_packages "${packages[@]}"
mark_done packages
