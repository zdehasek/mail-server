#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo mailserver config-drift [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
require_root
load_config
ensure_mail_db_password

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

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
  if diff -u "$rendered" "$dest"; then
    ok_state "config matches template: $dest"
  else
    fail_state "config drift detected: $dest"
  fi
}

failures=0
warnings=0
check_template "$ROOT_DIR/templates/nginx/sogo.conf.tmpl" /etc/nginx/sites-available/sogo.conf
check_template "$ROOT_DIR/templates/sogo/sogo.conf.tmpl" /etc/sogo/sogo.conf raw
check_template "$ROOT_DIR/templates/nginx/autoconfig.xml.tmpl" /etc/nginx/mail-autoconfig.xml raw
warn_state "config-drift is scoped to SOGo/webmail generated files; it does not audit every Postfix, Dovecot, Rspamd, DKIM, DMARC, Fail2ban, or SSH hardening file."

printf '\nSummary: %d drift(s), %d warning(s)\n' "$failures" "$warnings"
[[ "$failures" -eq 0 ]]
