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
  local port
  for port in 25 80 443 587 993; do
    if ss -ltn "sport = :$port" | awk 'NR>1 {found=1} END {exit found ? 0 : 1}'; then
      warn "Port $port is already listening. Installer may replace or conflict with an existing service."
    fi
  done
}

check_external_firewall_notice() {
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
