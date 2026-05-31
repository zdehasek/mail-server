#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo $0 [--config ./mail.env]"; }
parse_config_only_args "$@" || { usage; exit 0; }
require_root
load_config

cron_file="/etc/cron.d/mailserver-backup"
script_path="$(realpath "$ROOT_DIR/scripts/backup.sh")"
config_path="$(realpath "$CONFIG_FILE")"
log_path="/var/log/mailserver-backup.log"

rendered="$MANAGED_HEADER
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$BACKUP_CRON_SCHEDULE root $script_path --config $config_path >> $log_path 2>&1
"

write_file "$cron_file" "$rendered"
run chmod 0644 "$cron_file"
run systemctl enable --now cron

info "Backup cron installed: $cron_file"
info "Schedule: $BACKUP_CRON_SCHEDULE"
