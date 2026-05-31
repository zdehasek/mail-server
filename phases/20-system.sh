#!/usr/bin/env bash

run groupadd -g "$VMAIL_GID" -r vmail 2>/dev/null || true
run useradd -r -u "$VMAIL_UID" -g vmail -d "$VMAIL_ROOT" -s /usr/sbin/nologin vmail 2>/dev/null || true

run mkdir -p "$VMAIL_ROOT" /etc/mailserver/secrets /etc/mailserver/dkim /var/www/letsencrypt "$BACKUP_ROOT" /opt/roundcube /var/lib/roundcube /var/lib/radicale/collections
run chown -R vmail:vmail "$VMAIL_ROOT"
run chmod 0750 "$VMAIL_ROOT"
run chmod 0700 /etc/mailserver/secrets
run chown -R radicale:radicale /var/lib/radicale || true
run chown -R www-data:www-data /var/lib/roundcube
run chmod 0750 /var/lib/radicale/collections

if [[ "$DRY_RUN" != "true" ]]; then
  if [[ ! -f /etc/mailserver/secrets/rspamd-controller-password ]]; then
    openssl rand -base64 32 > /etc/mailserver/secrets/rspamd-controller-password
  fi
  chmod 0600 /etc/mailserver/secrets/rspamd-controller-password
fi

mark_done system
