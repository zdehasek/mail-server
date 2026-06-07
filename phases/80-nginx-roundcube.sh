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

roundcube_plugins="'archive', 'zipdownload', 'managesieve'"
if [[ "${ENABLE_ROUNDCUBE_CALENDAR:-true}" == "true" ]]; then
  roundcube_plugins="'archive', 'zipdownload', 'managesieve', 'libkolab', 'libcalendaring', 'calendar'"
  ROUNDCUBE_CALDAV_BASE_URL="${ROUNDCUBE_CALDAV_BASE_URL%/}/"
fi
export ROUNDCUBE_PLUGINS="$roundcube_plugins"
export ROUNDCUBE_CALDAV_BASE_URL="${ROUNDCUBE_CALDAV_BASE_URL:-https://$DAV_HOSTNAME/}"

archive="/tmp/roundcube-$ROUNDCUBE_VERSION.tar.gz"
if [[ "$DRY_RUN" == "true" ]]; then
  info "Would download Roundcube $ROUNDCUBE_VERSION from $ROUNDCUBE_URL"
  if [[ "${ENABLE_ROUNDCUBE_CALENDAR:-true}" == "true" ]]; then
    info "Would install texxasrulez/calendar $ROUNDCUBE_CALENDAR_VERSION and initialize CalDAV calendar tables"
  fi
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

  if [[ "${ENABLE_ROUNDCUBE_CALENDAR:-true}" == "true" ]]; then
    (
      cd /opt/roundcube/current
      export COMPOSER_ALLOW_SUPERUSER=1
      composer require --no-interaction --update-no-dev --no-plugins \
        "texxasrulez/calendar:$ROUNDCUBE_CALENDAR_VERSION" \
        "pear/http_request2:^2.7"
    )
    rm -rf \
      /opt/roundcube/current/plugins/calendar \
      /opt/roundcube/current/plugins/libcalendaring \
      /opt/roundcube/current/plugins/libkolab
    cp -a /opt/roundcube/current/vendor/texxasrulez/calendar /opt/roundcube/current/plugins/calendar
    cp -a /opt/roundcube/current/vendor/texxasrulez/libcalendaring /opt/roundcube/current/plugins/libcalendaring
    cp -a /opt/roundcube/current/vendor/texxasrulez/libkolab /opt/roundcube/current/plugins/libkolab
    install -d -m 0755 /opt/roundcube/current/plugins/libcalendaring/skins/elastic
    install -m 0644 /opt/roundcube/current/plugins/calendar/skins/elastic/elastic.min.css \
      /opt/roundcube/current/plugins/calendar/skins/elastic/calendar.css
    install -m 0644 /opt/roundcube/current/plugins/calendar/skins/elastic/elastic.min.css \
      /opt/roundcube/current/plugins/calendar/skins/elastic/fullcalendar.css
    install -m 0644 /opt/roundcube/current/plugins/calendar/skins/elastic/elastic.min.css \
      /opt/roundcube/current/plugins/libkolab/skins/elastic/libkolab.css
    install -m 0644 /opt/roundcube/current/plugins/calendar/skins/elastic/elastic.min.css \
      /opt/roundcube/current/plugins/libcalendaring/skins/elastic/libcal.css
    sed -i \
      's/CREATE INDEX ix_contact_type ON kolab_cache_dav_contact/CREATE INDEX ix_contact_dav_type ON kolab_cache_dav_contact/' \
      /opt/roundcube/current/plugins/libkolab/SQL/sqlite.initial.sql
    chown -R root:www-data \
      /opt/roundcube/current/plugins/calendar \
      /opt/roundcube/current/plugins/libcalendaring \
      /opt/roundcube/current/plugins/libkolab
  fi
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
  if [[ "${ENABLE_ROUNDCUBE_CALENDAR:-true}" == "true" ]] \
    && ! sqlite3 /var/lib/roundcube/roundcube.sqlite "SELECT 1 FROM system WHERE name = 'libkolab-version';" | grep -q 1; then
    /opt/roundcube/current/bin/initdb.sh --dir=/opt/roundcube/current/plugins/libkolab/SQL
  fi
  if [[ "${ENABLE_ROUNDCUBE_CALENDAR:-true}" == "true" ]] \
    && ! sqlite3 /var/lib/roundcube/roundcube.sqlite "SELECT 1 FROM system WHERE name = 'calendar-caldav-version';" | grep -q 1; then
    /opt/roundcube/current/bin/initdb.sh --dir=/opt/roundcube/current/plugins/calendar/drivers/caldav/SQL
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
