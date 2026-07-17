#!/usr/bin/env bash

check_command() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

check_ubuntu_2604() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release"
  # shellcheck source=/dev/null
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "26.04" ]]; then
    [[ "$FORCE" == "true" ]] || die "Only Ubuntu 26.04 is supported. Use --force to bypass."
    warn "Unsupported OS ${PRETTY_NAME:-unknown}; continuing because --force was set."
  fi
}

check_systemd() { [[ -d /run/systemd/system ]] || die "systemd is required."; }

check_dns() {
  check_command getent
  local resolved=""
  resolved="$(getent ahostsv4 "$MAIL_HOSTNAME" | awk '{print $1; exit}' || true)"
  if [[ -z "$resolved" ]]; then
    warn "$MAIL_HOSTNAME has no public IPv4 DNS result yet. Let's Encrypt will fail until DNS exists."
    return 0
  fi
  if [[ "$resolved" != "$SERVER_PUBLIC_IPV4" ]]; then
    [[ "$FORCE" == "true" ]] || die "$MAIL_HOSTNAME resolves to $resolved, expected $SERVER_PUBLIC_IPV4. Fix DNS or use --force."
    warn "DNS mismatch ignored because --force was set."
  fi
}

check_resources() {
  local mem_kb disk_kb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  disk_kb="$(df -Pk / | awk 'NR==2 {print $4}')"
  (( mem_kb >= 900000 )) || warn "Less than 1 GB RAM detected; SOGo/Rspamd/PostgreSQL may be tight."
  (( disk_kb >= 10000000 )) || warn "Less than 10 GB free disk detected."
}

check_ports() {
  check_command ss
  local port spec
  local name expected listener
  local ports=(
    "25:SMTP:master|postfix|smtpd"
    "80:HTTP / Let's Encrypt:nginx"
    "443:HTTPS:nginx"
    "587:SMTP submission:master|postfix|smtpd"
    "993:IMAPS:dovecot"
  )
  for spec in "${ports[@]}"; do
    IFS=: read -r port name expected <<< "$spec"
    if port_is_listening "$port"; then
      listener="$(port_listener_summary "$port")"
      if port_listener_has_expected "$port" "$expected"; then
        ok_state "port $port already listening: $name via $listener"
      elif [[ "$listener" == unknown\ process* ]]; then
        warn "Port $port ($name) is already listening, but the owner is hidden. Rerun with sudo so doctor can decide whether this is expected or a real conflict."
      else
        warn "Port $port ($name) is already listening on $listener. Stop or move that service before install, or run doctor --fix after install for managed repairs."
      fi
    fi
  done
}

check_external_firewall_notice() {
  [[ "${MAILSERVER_SKIP_PREFLIGHT_FIREWALL_NOTICE:-false}" == "true" ]] && return 0
  warn "Provider firewalls cannot be verified before mail services are listening. After setup, run: mailserver doctor"
}

run_preflight() {
  check_ubuntu_2604
  check_systemd
  check_dns
  check_resources
  check_ports
  check_external_firewall_notice
}
