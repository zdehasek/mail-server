#!/usr/bin/env bash

up() {
  ensure_mail_db_password

  write_file /etc/sogo/sogo.conf "$(replace_tokens "$ROOT_DIR/templates/sogo/sogo.conf.tmpl")"
  run chown root:sogo /etc/sogo/sogo.conf
  run chmod 0640 /etc/sogo/sogo.conf

  service_enable_now memcached
  service_enable_now sogo
  run systemctl restart sogo

  render_template "$ROOT_DIR/templates/nginx/sogo.conf.tmpl" /etc/nginx/sites-available/sogo.conf
  write_file /etc/nginx/mail-autoconfig.xml "$(replace_tokens "$ROOT_DIR/templates/nginx/autoconfig.xml.tmpl")"
  write_file /etc/nginx/apple-mail.mobileconfig "$(replace_tokens "$ROOT_DIR/templates/nginx/apple-mail.mobileconfig.tmpl")"
  run ln -sf /etc/nginx/sites-available/sogo.conf /etc/nginx/sites-enabled/sogo.conf
  run rm -f /etc/nginx/sites-enabled/roundcube.conf
  run rm -f /etc/nginx/sites-enabled/mailserver-acme.conf
  run rm -f /etc/nginx/sites-enabled/default
  run nginx -t
  service_enable_now nginx
  reload_or_restart nginx
  mark_done sogo
}

down() {
  stop_disable_service sogo
  stop_disable_service memcached
  stop_disable_service nginx

  run_rm /etc/sogo/sogo.conf
  run_rm /etc/nginx/sites-available/sogo.conf
  run_rm /etc/nginx/sites-enabled/sogo.conf
  run_rm /etc/nginx/mail-autoconfig.xml
  run_rm /etc/nginx/apple-mail.mobileconfig
}
