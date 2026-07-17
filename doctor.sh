#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/preflight.sh
source "$ROOT_DIR/lib/preflight.sh"

DOCTOR_FIX="false"
PREFLIGHT_ONLY="false"
DOCTOR_ARGS=()

usage() {
  cat <<'USAGE'
Usage: mailserver doctor [--fix] [--preflight-only] [--config PATH]

Runs local prerequisite checks plus DNS, SSL/TLS, service, config drift, and TLS
policy checks. Use --fix to apply safe local repairs such as opening UFW ports
and enabling installed mail services. DNS and provider firewall issues still
need manual/provider-side changes.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)
      DOCTOR_FIX="true"
      shift
      ;;
    --preflight-only)
      PREFLIGHT_ONLY="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      DOCTOR_ARGS+=("$1")
      shift
      ;;
  esac
done

parse_common_args "${DOCTOR_ARGS[@]}"
load_config
if [[ "$DOCTOR_FIX" == "true" ]]; then
  require_root
fi

apply_firewall_fixes() {
  if [[ "${ENABLE_UFW:-true}" != "true" ]]; then
    warn_state "UFW fix skipped because ENABLE_UFW=false"
    return 0
  fi
  if ! command -v ufw >/dev/null 2>&1; then
    warn_state "UFW fix skipped because ufw is not installed"
    return 0
  fi

  info "Opening required local UFW ports."
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw allow "${SSH_PORT}/tcp" comment SSH
  run ufw allow 25/tcp comment SMTP
  run ufw allow 80/tcp comment HTTP-ACME
  run ufw allow 443/tcp comment HTTPS
  run ufw allow 587/tcp comment SMTP-Submission
  run ufw allow 993/tcp comment IMAPS

  if ss -ltn "sport = :${SSH_PORT}" | awk 'NR>1 {found=1} END {exit found ? 0 : 1}'; then
    run ufw --force enable
  else
    warn_state "UFW rules were written, but UFW was not enabled because SSH port ${SSH_PORT} is not listening"
  fi
}

apply_service_fixes() {
  local service
  local services=(postgresql postfix dovecot nginx memcached sogo opendkim opendmarc fail2ban)
  [[ "${ENABLE_RSPAMD:-true}" == "true" ]] && services+=(rspamd)

  for service in "${services[@]}"; do
    if ! systemctl list-unit-files "$service.service" --no-legend 2>/dev/null | grep -q "^$service\\.service"; then
      warn_state "service fix skipped because $service is not installed"
      continue
    fi
    if systemctl is-active --quiet "$service"; then
      ok_state "service already active: $service"
      continue
    fi
    info "Enabling and starting $service."
    run systemctl enable --now "$service" || warn_state "could not start service: $service"
  done
}

apply_milter_fixes() {
  local service
  local status=0

  info "Configuring OpenDKIM and OpenDMARC TCP milter sockets."
  configure_milter_tcp_sockets

  for service in opendkim opendmarc postfix; do
    if ! systemctl list-unit-files "$service.service" --no-legend 2>/dev/null | grep -q "^$service\\.service"; then
      warn_state "milter fix skipped restart because $service is not installed"
      continue
    fi
    run systemctl restart "$service" || warn_state "could not restart service after milter socket fix: $service"
  done

  sleep 1
  if port_listener_has_expected 8891 "opendkim"; then
    ok_state "OpenDKIM milter is listening on 127.0.0.1:8891"
  else
    fail_state "OpenDKIM milter is still not listening on 127.0.0.1:8891 after restart"
    status=1
  fi
  if port_listener_has_expected 8893 "opendmarc"; then
    ok_state "OpenDMARC milter is listening on 127.0.0.1:8893"
  else
    fail_state "OpenDMARC milter is still not listening on 127.0.0.1:8893 after restart"
    status=1
  fi
  return "$status"
}

run_health_checks() {
  local status=0
  local config_drift_args=(--config "$CONFIG_FILE")
  [[ "$DOCTOR_FIX" == "true" ]] && config_drift_args+=(--fix)

  if [[ "$DOCTOR_FIX" == "true" ]]; then
    "$ROOT_DIR/scripts/config-drift.sh" "${config_drift_args[@]}" || status=$?
    ui_blank
  fi

  "$ROOT_DIR/scripts/dns-state.sh" --config "$CONFIG_FILE" || status=$?
  ui_blank
  "$ROOT_DIR/scripts/check-ssl.sh" --config "$CONFIG_FILE" || status=$?
  ui_blank
  "$ROOT_DIR/scripts/service-state.sh" --config "$CONFIG_FILE" || status=$?
  ui_blank
  if [[ "$DOCTOR_FIX" != "true" ]]; then
    "$ROOT_DIR/scripts/config-drift.sh" "${config_drift_args[@]}" || status=$?
    ui_blank
  fi
  "$ROOT_DIR/scripts/tls-policy-state.sh" --config "$CONFIG_FILE" || status=$?
  return "$status"
}

run_preflight

if [[ "$DOCTOR_FIX" == "true" ]]; then
  apply_firewall_fixes
  apply_service_fixes
  apply_milter_fixes
  ui_blank
fi

if [[ "$PREFLIGHT_ONLY" == "true" ]]; then
  info "Preflight checks completed. Run mailserver doctor after installation for DNS, TLS, and service checks."
else
  run_health_checks
fi

info "Doctor checks completed. Warnings above may still require manual DNS/provider action."
