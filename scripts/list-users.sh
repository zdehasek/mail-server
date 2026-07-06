#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

usage() { echo "Usage: sudo mailserver list-users [--config PATH]"; }
parse_config_only_args "$@" || { usage; exit 0; }
[[ "${#POSITIONAL[@]}" -eq 0 ]] || { usage; exit 1; }
require_root
load_config

psql_mail <<'SQL'
SELECT
  CASE active WHEN true THEN 'active' ELSE 'inactive' END AS status,
  email,
  full_name,
  created_at
FROM users
ORDER BY active DESC, email;
SQL
