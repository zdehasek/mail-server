#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo mailserver rspamd-state [status|counters|commands] [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
require_root
load_config

action="${POSITIONAL[0]:-status}"
[[ "${#POSITIONAL[@]}" -le 1 ]] || { usage; exit 1; }

password_file="${RSPAMD_CONTROLLER_PASSWORD_FILE:-/etc/mailserver/secrets/rspamd-controller-password}"
[[ -f "$password_file" ]] || die "Rspamd controller password file not found: $password_file"
command -v rspamc >/dev/null 2>&1 || die "rspamc is required."

password="$(<"$password_file")"
rspamc_ctl=(rspamc -h 127.0.0.1:11334 -P "$password")

case "$action" in
  status)
    "${rspamc_ctl[@]}" stat
    ;;
  counters)
    "${rspamc_ctl[@]}" counters
    ;;
  commands)
    "${rspamc_ctl[@]}" --commands
    ;;
  *)
    die "Unknown rspamd-state action: $action"
    ;;
esac

if [[ ! -d /var/lib/rspamd/quarantine ]]; then
  info "Rspamd quarantine directory is not present; this stack exposes status/counters, not a mailcow-style quarantine UI."
fi
