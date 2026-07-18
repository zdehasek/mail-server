#!/usr/bin/env bash

up() {
  if [[ "${ENABLE_FAIL2BAN:-true}" == "true" ]]; then
    render_template "$ROOT_DIR/templates/fail2ban/jail.local.tmpl" /etc/fail2ban/jail.d/mailserver.local
    service_enable_now fail2ban
    reload_or_restart fail2ban
  fi

  if [[ "${ENABLE_SSH_HARDENING:-true}" == "true" ]]; then
    ssh_allow_users="$SSH_ALLOW_USERS"
    if [[ -z "$ssh_allow_users" && -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
      ssh_allow_users="$SUDO_USER"
    fi

    if [[ -z "$ssh_allow_users" ]]; then
      warn "SSH_ALLOW_USERS is empty and no sudo user was detected; skipping SSH hardening to avoid lockout."
    else
      ssh_key_user="${ssh_allow_users%% *}"
      if [[ "$DRY_RUN" != "true" && "$FORCE" != "true" && ! -s "/home/$ssh_key_user/.ssh/authorized_keys" ]]; then
        die "Refusing SSH hardening: /home/$ssh_key_user/.ssh/authorized_keys is missing or empty. Set SSH_ALLOW_USERS to a key-enabled user or rerun with --force."
      fi

      SSH_ALLOW_USERS_DIRECTIVE="AllowUsers $ssh_allow_users"
      render_template "$ROOT_DIR/templates/ssh/99-mailserver-hardening.conf.tmpl" /etc/ssh/sshd_config.d/99-mailserver-hardening.conf
      if [[ "$DRY_RUN" != "true" ]]; then
        /usr/sbin/sshd -t
      fi
      run systemctl reload ssh || run systemctl reload sshd || run systemctl restart ssh || run systemctl restart sshd
    fi
  fi

  if [[ "${ENABLE_UFW:-true}" == "true" ]]; then
    if [[ "${UFW_RESET_RULES:-true}" == "true" ]]; then
      run ufw --force reset
    fi
    run ufw default deny incoming
    run ufw default allow outgoing
    run ufw logging on
    run ufw allow "${SSH_PORT}/tcp" comment SSH
    run ufw allow 25/tcp comment SMTP
    run ufw allow 80/tcp comment HTTP-ACME
    run ufw allow 443/tcp comment HTTPS
    run ufw allow 587/tcp comment SMTP-Submission
    run ufw allow 993/tcp comment IMAPS
    if ss -ltn "sport = :${SSH_PORT}" | awk 'NR>1 {found=1} END {exit found ? 0 : 1}'; then
      run ufw --force enable
    else
      warn "SSH port ${SSH_PORT} is not listening; refusing to enable UFW automatically."
    fi
  fi

  mark_done security
}

down() {
  stop_disable_service fail2ban
  run_rm /etc/fail2ban/jail.d/mailserver.local
  run_rm /etc/ssh/sshd_config.d/99-mailserver-hardening.conf
  reset_firewall
  reload_ssh_after_cleanup
}
