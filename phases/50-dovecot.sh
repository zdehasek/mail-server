#!/usr/bin/env bash

render_template "$ROOT_DIR/templates/dovecot/dovecot.conf.tmpl" /etc/dovecot/dovecot.conf
render_template "$ROOT_DIR/templates/dovecot/dovecot-sql.conf.ext.tmpl" /etc/dovecot/dovecot-sql.conf.ext
run install -d -o root -g root -m 0755 /etc/dovecot/sieve/before.d
render_template "$ROOT_DIR/templates/dovecot/sent-copies.sieve.tmpl" /etc/dovecot/sieve/before.d/sent-copies.sieve
run chown root:dovecot /etc/dovecot/dovecot-sql.conf.ext
run chmod 0640 /etc/dovecot/dovecot-sql.conf.ext
run chown root:root /etc/dovecot/sieve/before.d/sent-copies.sieve
run chmod 0644 /etc/dovecot/sieve/before.d/sent-copies.sieve
run sievec /etc/dovecot/sieve/before.d/sent-copies.sieve
run doveconf -n >/dev/null
service_enable_now dovecot
reload_or_restart dovecot
mark_done dovecot
