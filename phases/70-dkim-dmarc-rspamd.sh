#!/usr/bin/env bash

render_template "$ROOT_DIR/templates/opendkim/opendkim.conf.tmpl" /etc/opendkim.conf
refresh_opendkim_domain_maps
render_template "$ROOT_DIR/templates/opendmarc/opendmarc.conf.tmpl" /etc/opendmarc.conf
configure_milter_tcp_sockets

service_enable_now opendkim
service_enable_now opendmarc
run systemctl restart opendkim
run systemctl restart opendmarc

if [[ "${ENABLE_RSPAMD:-true}" == "true" ]]; then
  render_template "$ROOT_DIR/templates/rspamd/milter_headers.conf.tmpl" /etc/rspamd/local.d/milter_headers.conf
  render_template "$ROOT_DIR/templates/rspamd/actions.conf.tmpl" /etc/rspamd/local.d/actions.conf
  run rspamadm configtest
  service_enable_now rspamd
  reload_or_restart rspamd
fi

mark_done dkim-dmarc-rspamd
