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
if [[ "${ROUNDCUBE_ENABLE_CALENDAR:-true}" == "true" ]]; then
  roundcube_plugins+=", 'libcalendaring', 'libkolab', 'calendar'"
fi
export ROUNDCUBE_PLUGINS="$roundcube_plugins"

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

if [[ "$DRY_RUN" == "true" ]]; then
  info "Would initialize Roundcube SQLite database at /var/lib/roundcube/roundcube.sqlite"
else
  if [[ ! -f /var/lib/roundcube/roundcube.sqlite ]]; then
    sqlite3 /var/lib/roundcube/roundcube.sqlite < /opt/roundcube/current/SQL/sqlite.initial.sql
  fi
  chown www-data:www-data /var/lib/roundcube/roundcube.sqlite
  chmod 0640 /var/lib/roundcube/roundcube.sqlite
fi

install_roundcube_skin() {
  local archive_dir skin_archive skin_tmp skin_src

  if [[ "${ROUNDCUBE_SKIN:-elastic}" == "elastic" ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would install Roundcube skin ${ROUNDCUBE_SKIN} from ${ROUNDCUBE_SKIN_URL}"
    return 0
  fi

  archive_dir="$(mktemp -d)"
  skin_archive="$archive_dir/skin.zip"
  skin_tmp="$archive_dir/extract"
  curl -fsSL "$ROUNDCUBE_SKIN_URL" -o "$skin_archive"
  unzip -q "$skin_archive" -d "$skin_tmp"
  skin_src="$(find "$skin_tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "$skin_src" ]] || die "Could not find extracted Roundcube skin directory in $skin_tmp"
  rm -rf "/opt/roundcube/current/skins/$ROUNDCUBE_SKIN"
  cp -a "$skin_src" "/opt/roundcube/current/skins/$ROUNDCUBE_SKIN"
  rm -rf "/opt/roundcube/current/skins/$ROUNDCUBE_SKIN/.git"
  find "/opt/roundcube/current/skins/$ROUNDCUBE_SKIN" -type d -exec chmod 0755 {} +
  find "/opt/roundcube/current/skins/$ROUNDCUBE_SKIN" -type f -exec chmod 0644 {} +
  rm -rf "$archive_dir"
}

install_roundcube_calendar_plugins() {
  if [[ "${ROUNDCUBE_ENABLE_CALENDAR:-true}" != "true" ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "Would install Roundcube calendar plugins and initialize calendar tables"
    return 0
  fi

  COMPOSER_ALLOW_SUPERUSER=1 composer require \
    texxasrulez/calendar:^3.4 \
    texxasrulez/libcalendaring:^3.4 \
    texxasrulez/libkolab:^3.4 \
    pear/http_request2:^2.7 \
    pear/net_url2:^2.2 \
    --working-dir=/opt/roundcube/current \
    --no-interaction \
    --no-plugins

  COMPOSER_ALLOW_SUPERUSER=1 composer update \
    guzzlehttp/guzzle \
    guzzlehttp/psr7 \
    -W \
    --working-dir=/opt/roundcube/current \
    --no-interaction \
    --no-plugins

  local plugin
  for plugin in libkolab libcalendaring calendar; do
    rm -rf "/opt/roundcube/current/plugins/$plugin"
    cp -a "/opt/roundcube/current/vendor/texxasrulez/$plugin" "/opt/roundcube/current/plugins/$plugin"
  done
  find /opt/roundcube/current/plugins/libkolab /opt/roundcube/current/plugins/libcalendaring /opt/roundcube/current/plugins/calendar -type d -exec chmod 0755 {} +
  find /opt/roundcube/current/plugins/libkolab /opt/roundcube/current/plugins/libcalendaring /opt/roundcube/current/plugins/calendar -type f -exec chmod 0644 {} +

  sqlite3 /var/lib/roundcube/roundcube.sqlite < /opt/roundcube/current/plugins/libkolab/SQL/sqlite.initial.sql || true
  sqlite3 /var/lib/roundcube/roundcube.sqlite <<'SQL'
CREATE TABLE IF NOT EXISTS kolab_cache_dav_event (
  folder_id INTEGER NOT NULL,
  uid VARCHAR(512) NOT NULL,
  etag VARCHAR(128) NOT NULL,
  created DATETIME DEFAULT NULL,
  changed DATETIME DEFAULT NULL,
  data TEXT NOT NULL,
  tags TEXT NOT NULL,
  words TEXT NOT NULL,
  dtstart DATETIME,
  dtend DATETIME,
  PRIMARY KEY(folder_id, uid)
);
CREATE TABLE IF NOT EXISTS kolab_cache_dav_task (
  folder_id INTEGER NOT NULL,
  uid VARCHAR(512) NOT NULL,
  etag VARCHAR(128) NOT NULL,
  created DATETIME DEFAULT NULL,
  changed DATETIME DEFAULT NULL,
  data TEXT NOT NULL,
  tags TEXT NOT NULL,
  words TEXT NOT NULL,
  dtstart DATETIME,
  dtend DATETIME,
  PRIMARY KEY(folder_id, uid)
);
INSERT OR REPLACE INTO system (name, value) VALUES ('libkolab-version', '2023111200');
SQL

  if ! sqlite3 /var/lib/roundcube/roundcube.sqlite "SELECT value FROM system WHERE name='calendar-caldav-version';" | grep -q .; then
    sqlite3 /var/lib/roundcube/roundcube.sqlite < /opt/roundcube/current/plugins/calendar/drivers/caldav/SQL/sqlite.initial.sql
  fi

  cat > /opt/roundcube/current/plugins/calendar/config.inc.php <<PHP
<?php

\$config['calendar_driver'] = 'caldav';
\$config['calendar_caldav_server'] = '$ROUNDCUBE_CALDAV_SERVER';
\$config['calendar_caldav_url'] = '$ROUNDCUBE_CALDAV_URL';
\$config['calendar_default_view'] = 'month';
\$config['calendar_contact_birthdays'] = true;
\$config['calendar_timeslots'] = 4;
\$config['calendar_agenda_range'] = 60;
\$config['calendar_first_day'] = 1;
\$config['calendar_first_hour'] = 6;
\$config['calendar_work_start'] = 6;
\$config['calendar_work_end'] = 18;
\$config['calendar_time_indicator'] = true;
\$config['calendar_show_weekno'] = 0;
\$config['calendar_default_alarm_type'] = '';
\$config['calendar_default_alarm_offset'] = '-15M';
\$config['calendar_event_coloring'] = 0;
\$config['calendar_allow_invite_shared'] = false;
\$config['calendar_allow_itip_uninvited'] = true;
\$config['calendar_itip_send_option'] = 3;
\$config['calendar_itip_after_action'] = 0;
\$config['calendar_freebusy_trigger'] = false;
\$config['calendar_include_freebusy_data'] = 1;
\$config['calendar_itip_smtp_server'] = null;
\$config['calendar_itip_smtp_user'] = '%u';
\$config['calendar_itip_smtp_pass'] = '%p';
\$config['kolab_invitation_calendars'] = false;
\$config['calendar_freebusy_session_auth_url'] = null;
PHP
  chown root:www-data /opt/roundcube/current/plugins/calendar/config.inc.php
  chmod 0640 /opt/roundcube/current/plugins/calendar/config.inc.php
}

install_roundcube_skin
install_roundcube_calendar_plugins

render_template "$ROOT_DIR/templates/roundcube/config.inc.php.tmpl" /opt/roundcube/current/config/config.inc.php
run chown root:www-data /opt/roundcube/current/config/config.inc.php
run chmod 0640 /opt/roundcube/current/config/config.inc.php

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
