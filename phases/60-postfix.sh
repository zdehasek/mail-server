#!/usr/bin/env bash

ensure_mail_db_password

render_template "$ROOT_DIR/templates/postfix/main.cf.tmpl" /etc/postfix/main.cf
render_template "$ROOT_DIR/templates/postfix/master.cf.tmpl" /etc/postfix/master.cf
render_template "$ROOT_DIR/templates/postfix/pgsql-domains.cf.tmpl" /etc/postfix/pgsql-domains.cf
render_template "$ROOT_DIR/templates/postfix/pgsql-users.cf.tmpl" /etc/postfix/pgsql-users.cf
render_template "$ROOT_DIR/templates/postfix/pgsql-aliases.cf.tmpl" /etc/postfix/pgsql-aliases.cf
render_template "$ROOT_DIR/templates/postfix/pgsql-sender-bcc.cf.tmpl" /etc/postfix/pgsql-sender-bcc.cf
run chown root:postfix /etc/postfix/pgsql-*.cf
run chmod 0640 /etc/postfix/pgsql-*.cf
run postfix check
service_enable_now postfix
reload_or_restart postfix
mark_done postfix
