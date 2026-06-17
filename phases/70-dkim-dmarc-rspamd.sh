#!/usr/bin/env bash

dkim_dir="/etc/mailserver/dkim/$PRIMARY_DOMAIN"
run mkdir -p "$dkim_dir"
if [[ "$DRY_RUN" != "true" && ! -f "$dkim_dir/$DKIM_SELECTOR.private" ]]; then
  opendkim-genkey -b 2048 -d "$PRIMARY_DOMAIN" -s "$DKIM_SELECTOR" -D "$dkim_dir"
  chown -R opendkim:opendkim "$dkim_dir"
  chmod 0600 "$dkim_dir/$DKIM_SELECTOR.private"
fi

render_template "$ROOT_DIR/templates/opendkim/opendkim.conf.tmpl" /etc/opendkim.conf
render_template "$ROOT_DIR/templates/opendkim/signing.table.tmpl" /etc/opendkim/signing.table
render_template "$ROOT_DIR/templates/opendkim/key.table.tmpl" /etc/opendkim/key.table
render_template "$ROOT_DIR/templates/opendkim/trusted.hosts.tmpl" /etc/opendkim/trusted.hosts
render_template "$ROOT_DIR/templates/opendmarc/opendmarc.conf.tmpl" /etc/opendmarc.conf

service_enable_now opendkim
service_enable_now opendmarc
reload_or_restart opendkim
reload_or_restart opendmarc

if [[ "${ENABLE_RSPAMD:-true}" == "true" ]]; then
  render_template "$ROOT_DIR/templates/rspamd/milter_headers.conf.tmpl" /etc/rspamd/local.d/milter_headers.conf
  render_template "$ROOT_DIR/templates/rspamd/actions.conf.tmpl" /etc/rspamd/local.d/actions.conf
  run rspamadm configtest
  service_enable_now rspamd
  reload_or_restart rspamd
else
  warn "ENABLE_RSPAMD=false; Postfix will be configured without the Rspamd spam-filtering milter."
fi

mark_done dkim-dmarc-rspamd
