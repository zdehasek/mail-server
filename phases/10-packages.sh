#!/usr/bin/env bash

packages=(
  ca-certificates curl gnupg lsb-release dnsutils netcat-openbsd openssl sqlite3 tar unzip cron
  postgresql postgresql-client
  postfix postfix-pgsql postfix-policyd-spf-python
  dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sieve dovecot-managesieved dovecot-pgsql
  nginx certbot apache2-utils
  sogo sogo-activesync memcached
  opendkim opendkim-tools opendmarc rspamd fail2ban ufw
)

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would install PostgreSQL-backed mail and SOGo packages"
else
  printf '%s\n' \
    'opendmarc opendmarc/dbconfig-install boolean false' | debconf-set-selections
fi

if [[ "${ENABLE_CLAMAV:-false}" == "true" ]]; then
  packages+=(clamav-daemon clamav-freshclam)
fi

install_packages "${packages[@]}"
mark_done packages
