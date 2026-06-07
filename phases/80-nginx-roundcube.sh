#!/usr/bin/env bash

if [[ "$DRY_RUN" != "true" && ! -f /etc/mailserver/secrets/roundcube-des-key ]]; then
  openssl rand -base64 24 > /etc/mailserver/secrets/roundcube-des-key
  chmod 0600 /etc/mailserver/secrets/roundcube-des-key
fi

roundcube_key="dry-run-roundcube-key"
if [[ "$DRY_RUN" != "true" ]]; then
  roundcube_key="$(tr -d '\n' < /etc/mailserver/secrets/roundcube-des-key | cut -c1-24)"
fi
export ROUNDCUBE_DES_KEY="$roundcube_key"

archive="/tmp/roundcube-$ROUNDCUBE_VERSION.tar.gz"
if [[ "$DRY_RUN" == "true" ]]; then
  info "Would download Roundcube $ROUNDCUBE_VERSION from $ROUNDCUBE_URL"
else
  curl -fsSL "$ROUNDCUBE_URL" -o "$archive"
  printf '%s  %s\n' "$ROUNDCUBE_SHA256" "$archive" | sha256sum -c -
  rm -rf "/opt/roundcube/releases/$ROUNDCUBE_VERSION"
  install -d -o www-data -g www-data "/opt/roundcube/releases/$ROUNDCUBE_VERSION"
  tar -xzf "$archive" -C "/opt/roundcube/releases/$ROUNDCUBE_VERSION" --strip-components=1
  ln -sfn "/opt/roundcube/releases/$ROUNDCUBE_VERSION" /opt/roundcube/current
  install -d -o www-data -g www-data /var/lib/roundcube/temp /var/log/roundcube
  rm -rf /opt/roundcube/current/temp /opt/roundcube/current/logs
  ln -sfn /var/lib/roundcube/temp /opt/roundcube/current/temp
  ln -sfn /var/log/roundcube /opt/roundcube/current/logs
fi

render_template "$ROOT_DIR/templates/roundcube/config.inc.php.tmpl" /opt/roundcube/current/config/config.inc.php
run chown root:www-data /opt/roundcube/current/config/config.inc.php
run chmod 0640 /opt/roundcube/current/config/config.inc.php

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would initialize Roundcube SQLite database at /var/lib/roundcube/roundcube.sqlite"
else
  if [[ ! -f /var/lib/roundcube/roundcube.sqlite ]]; then
    sqlite3 /var/lib/roundcube/roundcube.sqlite < /opt/roundcube/current/SQL/sqlite.initial.sql
  fi
  chown www-data:www-data /var/lib/roundcube/roundcube.sqlite
  chmod 0640 /var/lib/roundcube/roundcube.sqlite
fi

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would enable installed PHP-FPM service"
else
  php_fpm_unit=""
  for service_file in /usr/lib/systemd/system/php*-fpm.service /lib/systemd/system/php*-fpm.service; do
    [[ -f "$service_file" ]] || continue
    php_fpm_unit="$(basename "$service_file")"
    break
  done
  [[ -n "$php_fpm_unit" ]] || die "No php*-fpm.service unit found."
  systemctl enable --now "$php_fpm_unit"
fi
if [[ "$DRY_RUN" != "true" ]]; then
  for socket in /run/php/php*-fpm.sock; do
    [[ -S "$socket" ]] || continue
    [[ "$(basename "$socket")" != "php-fpm.sock" ]] || continue
    ln -sfn "$socket" /run/php/php-fpm.sock
    break
  done
fi

render_template "$ROOT_DIR/templates/nginx/roundcube.conf.tmpl" /etc/nginx/sites-available/roundcube.conf
run ln -sf /etc/nginx/sites-available/roundcube.conf /etc/nginx/sites-enabled/roundcube.conf
run rm -f /etc/nginx/sites-enabled/mailserver-acme.conf
run rm -f /etc/nginx/sites-enabled/default
run nginx -t
service_enable_now nginx
reload_or_restart nginx
mark_done nginx-roundcube
