#!/usr/bin/env bash

if [[ "${ENABLE_FAIL2BAN:-true}" == "true" ]]; then
  render_template "$ROOT_DIR/templates/fail2ban/jail.local.tmpl" /etc/fail2ban/jail.d/mailserver.local
  service_enable_now fail2ban
  reload_or_restart fail2ban
fi

if [[ "${ENABLE_UFW:-true}" == "true" ]]; then
  run ufw allow 22/tcp
  run ufw allow 25/tcp
  run ufw allow 80/tcp
  run ufw allow 443/tcp
  run ufw allow 587/tcp
  run ufw allow 993/tcp
  if ss -ltn 'sport = :22' | awk 'NR>1 {found=1} END {exit found ? 0 : 1}'; then
    run ufw --force enable
  else
    warn "SSH port 22 is not listening; refusing to enable UFW automatically."
  fi
fi

mark_done security
