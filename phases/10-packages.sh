#!/usr/bin/env bash

phase_packages() {
  local support_packages=(
    ca-certificates curl gnupg jq lsb-release dnsutils netcat-openbsd openssl sqlite3 tar unzip cron
  )
  local service_packages=(
    postgresql postgresql-client
    postfix postfix-pgsql postfix-policyd-spf-python
    dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sieve dovecot-managesieved dovecot-pgsql
    nginx certbot apache2-utils
    sogo sogo-activesync memcached
    opendkim opendkim-tools opendmarc rspamd fail2ban ufw
  )

  if [[ "${ENABLE_CLAMAV:-false}" == "true" ]]; then
    service_packages+=(clamav-daemon clamav-freshclam)
  fi

  printf '%s\n' "${support_packages[@]}" "${service_packages[@]}"
}

phase_removable_packages() {
  local service_packages=(
    postgresql postgresql-client
    postfix postfix-pgsql postfix-policyd-spf-python
    dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sieve dovecot-managesieved dovecot-pgsql
    nginx certbot apache2-utils
    sogo sogo-activesync memcached
    opendkim opendkim-tools opendmarc rspamd fail2ban ufw
    clamav-daemon clamav-freshclam
  )

  printf '%s\n' "${service_packages[@]}"
}

up() {
  local packages=()
  mapfile -t packages < <(phase_packages)

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would install PostgreSQL-backed mail and SOGo packages"
  else
    printf '%s\n' \
      'opendmarc opendmarc/dbconfig-install boolean false' | debconf-set-selections
  fi

  install_packages "${packages[@]}"
  mark_done packages
}

down() {
  local installed=()
  local package

  command -v dpkg-query >/dev/null 2>&1 || {
    warn "dpkg-query not found; skipping package purge"
    return 0
  }

  while IFS= read -r package; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
      installed+=("$package")
    fi
  done < <(phase_removable_packages)

  if [[ "${#installed[@]}" -eq 0 ]]; then
    info "No mailserver packages are installed"
    return 0
  fi

  run env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${installed[@]}"
  run env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
}
