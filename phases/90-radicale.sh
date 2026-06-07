#!/usr/bin/env bash

render_template "$ROOT_DIR/templates/radicale/config.tmpl" /etc/radicale/config
render_template "$ROOT_DIR/templates/radicale/rights.tmpl" /etc/radicale/rights
run touch /etc/radicale/users
run chown radicale:radicale /etc/radicale/users /etc/radicale/config /etc/radicale/rights
run chmod 0640 /etc/radicale/users /etc/radicale/config /etc/radicale/rights
service_enable_now radicale
run systemctl restart radicale
mark_done radicale
