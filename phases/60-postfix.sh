#!/usr/bin/env bash

render_template "$ROOT_DIR/templates/postfix/main.cf.tmpl" /etc/postfix/main.cf
render_template "$ROOT_DIR/templates/postfix/master.cf.tmpl" /etc/postfix/master.cf
render_template "$ROOT_DIR/templates/postfix/sqlite-domains.cf.tmpl" /etc/postfix/sqlite-domains.cf
render_template "$ROOT_DIR/templates/postfix/sqlite-users.cf.tmpl" /etc/postfix/sqlite-users.cf
render_template "$ROOT_DIR/templates/postfix/sqlite-aliases.cf.tmpl" /etc/postfix/sqlite-aliases.cf
run postfix check
service_enable_now postfix
reload_or_restart postfix
mark_done postfix
