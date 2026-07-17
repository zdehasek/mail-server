#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/common.sh disable=SC1091
source "$ROOT_DIR/lib/common.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

dkim_file="$tmp_dir/default.txt"
cat > "$dkim_file" <<'DKIM'
default._domainkey IN TXT ( "v=DKIM1; h=sha256; k=rsa; "
  "p=ABC123" ) ; ----- DKIM key default for example.com
DKIM

output="$(format_dkim_dns_record_file "$dkim_file" "example.com")"
expected='default._domainkey.example.com. TXT "v=DKIM1; h=sha256; k=rsa; p=ABC123"'

if [[ "$output" != "$expected" ]]; then
  printf 'Expected:\n%s\n\nActual:\n%s\n' "$expected" "$output" >&2
  exit 1
fi

printf 'DKIM DNS formatting ok\n'
