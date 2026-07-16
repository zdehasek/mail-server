#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo mailserver config-drift [--fix] [--config PATH]"; }

FIX_DRIFT="false"
CONFIG_DRIFT_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)
      FIX_DRIFT="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      CONFIG_DRIFT_ARGS+=("$1")
      shift
      ;;
  esac
done

parse_config_only_args "${CONFIG_DRIFT_ARGS[@]}" || { usage; exit 0; }
require_root
load_config
ensure_mail_db_password

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

fixes=0
nginx_fixed="false"
sogo_fixed="false"

service_unit_exists() {
  local service="$1"
  systemctl list-unit-files "$service.service" --no-legend 2>/dev/null | grep -q "^$service\\.service"
}

check_template() {
  local src="$1"
  local dest="$2"
  local mode="${3:-managed}"
  local rendered
  rendered="$tmp_dir/$(basename "$dest")"

  if [[ "$mode" == "raw" ]]; then
    replace_tokens "$src" > "$rendered"
  else
    render_template "$src" "$rendered"
  fi
  if [[ -f "$dest" ]] && cmp -s "$rendered" "$dest"; then
    ok_state "config matches template: $dest"
  else
    if [[ "$FIX_DRIFT" == "true" ]]; then
      if [[ "$mode" == "raw" ]]; then
        write_file "$dest" "$(replace_tokens "$src")"
      else
        render_template "$src" "$dest"
      fi
      fixes=$((fixes + 1))
      ok_state "fixed config drift: $dest"
      case "$dest" in
        /etc/nginx/*) nginx_fixed="true" ;;
        /etc/sogo/*) sogo_fixed="true" ;;
      esac
    elif [[ ! -e "$dest" ]]; then
      fail_state "managed config missing: $dest (run sudo mailserver doctor --fix)"
    else
      fail_state "managed config drift detected: $dest (run sudo mailserver doctor --fix)"
    fi
  fi
}

failures=0
warnings=0
check_template "$ROOT_DIR/templates/nginx/sogo.conf.tmpl" /etc/nginx/sites-available/sogo.conf
check_template "$ROOT_DIR/templates/sogo/sogo.conf.tmpl" /etc/sogo/sogo.conf raw
check_template "$ROOT_DIR/templates/nginx/autoconfig.xml.tmpl" /etc/nginx/mail-autoconfig.xml raw
check_template "$ROOT_DIR/templates/nginx/apple-mail.mobileconfig.tmpl" /etc/nginx/apple-mail.mobileconfig raw

if [[ "$sogo_fixed" == "true" ]]; then
  if getent group sogo >/dev/null 2>&1; then
    run chown root:sogo /etc/sogo/sogo.conf
    run chmod 0640 /etc/sogo/sogo.conf
  else
    warn_state "SOGo ownership fix skipped because group sogo does not exist"
  fi
  if service_unit_exists sogo; then
    reload_or_restart sogo
  else
    warn_state "SOGo reload skipped because sogo.service is not installed"
  fi
fi

if [[ "$nginx_fixed" == "true" ]]; then
  run ln -sf /etc/nginx/sites-available/sogo.conf /etc/nginx/sites-enabled/sogo.conf
  run rm -f /etc/nginx/sites-enabled/roundcube.conf
  run rm -f /etc/nginx/sites-enabled/mailserver-acme.conf
  run rm -f /etc/nginx/sites-enabled/default
  if command -v nginx >/dev/null 2>&1; then
    run nginx -t
  else
    warn_state "nginx config test skipped because nginx is not installed"
  fi
  if service_unit_exists nginx; then
    reload_or_restart nginx
  else
    warn_state "nginx reload skipped because nginx.service is not installed"
  fi
fi

warn_state "config-drift is scoped to SOGo/webmail generated files; it does not audit every Postfix, Dovecot, Rspamd, DKIM, DMARC, Fail2ban, or SSH hardening file."

printf '\nSummary: %d drift(s), %d warning(s), %d fixed\n' "$failures" "$warnings" "$fixes"
[[ "$failures" -eq 0 ]]
