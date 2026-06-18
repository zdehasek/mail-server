#!/usr/bin/env bash

# shellcheck source=../lib/dkim.sh
source "$ROOT_DIR/lib/dkim.sh"

render_template "$ROOT_DIR/templates/opendkim/opendkim.conf.tmpl" /etc/opendkim.conf
sync_dkim_domains
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
