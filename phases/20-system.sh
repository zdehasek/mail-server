#!/usr/bin/env bash

up() {
  run groupadd -g "$VMAIL_GID" -r vmail 2>/dev/null || true
  run useradd -r -u "$VMAIL_UID" -g vmail -d "$VMAIL_ROOT" -s /usr/sbin/nologin vmail 2>/dev/null || true

  run mkdir -p "$VMAIL_ROOT" /etc/mailserver/secrets /etc/mailserver/dkim /var/www/letsencrypt "$BACKUP_ROOT" /var/log/sogo
  run chown -R vmail:vmail "$VMAIL_ROOT"
  run chmod 0750 "$VMAIL_ROOT"
  run chmod 0700 /etc/mailserver/secrets
  run chown -R sogo:sogo /var/log/sogo || true

  if [[ "$DRY_RUN" != "true" ]]; then
    if [[ ! -f /etc/mailserver/secrets/rspamd-controller-password ]]; then
      openssl rand -base64 32 > /etc/mailserver/secrets/rspamd-controller-password
    fi
    chmod 0600 /etc/mailserver/secrets/rspamd-controller-password
  fi

  mark_done system
}

down() {
  if [[ "$CONFIG_FILE" == /* ]]; then
    run_rm "$CONFIG_FILE"
  else
    warn "Setup config path is not absolute; not deleting it: $CONFIG_FILE"
  fi

  run_rm "$VMAIL_ROOT"
  run_rm "$BACKUP_DIR"
  run_rm "$BACKUP_ROOT"
  run_rm /etc/mailserver
  run_rm /var/www/letsencrypt
  run_rm /etc/cron.d/mailserver-backup
  run_rm /var/log/mailserver-backup.log
  run_rm /var/log/sogo

  if getent passwd vmail >/dev/null 2>&1; then
    run userdel vmail || true
  fi
  if getent group vmail >/dev/null 2>&1; then
    run groupdel vmail || true
  fi
}
