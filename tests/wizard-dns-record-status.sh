#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export MAILSERVER_SOURCE_ONLY=true
export NO_COLOR=1
export COLUMNS=120

# shellcheck source=../mailserver.sh disable=SC1091
source "$ROOT_DIR/mailserver.sh"

dns_records='Publish these DNS records:

example.com. MX 10 mail.example.com.
mail.example.com. A 203.0.113.10
example.com. TXT "v=spf1 mx -all"
_dmarc.example.com. TXT "v=DMARC1; p=none; rua=mailto:dmarc@example.com; adkim=s; aspf=s"
default._domainkey.example.com. TXT "v=DKIM1; k=rsa; p=ABC123"

Provider PTR/rDNS must be:
203.0.113.10 -> mail.example.com'

dns_output='== DNS state for example.com ==
✅ OK    example.com. MX 10 mail.example.com.
❌ FAIL  mail.example.com A expected: mail.example.com. A 203.0.113.10; got: <none>
✅ OK    example.com. TXT "v=spf1 mx -all"
❌ FAIL  _dmarc.example.com TXT expected: _dmarc.example.com. TXT "v=DMARC1; p=none; rua=mailto:dmarc@example.com; adkim=s; aspf=s"; got: <none>
✅ OK    default._domainkey.example.com. TXT "v=DKIM1; k=rsa; p=ABC123"
❌ FAIL  203.0.113.10 PTR/rDNS expected: 203.0.113.10 -> mail.example.com; got: <none>
Summary: 3 failure(s), 0 warning(s)'

output="$(wizard_records "$dns_records" "$dns_output")"
visible_output="$(sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g' <<< "$output")"

assert_contains() {
  local needle="$1"
  if [[ "$visible_output" != *"$needle"* ]]; then
    printf 'Expected output to contain:\n%s\n\nActual output:\n%s\n' "$needle" "$visible_output" >&2
    exit 1
  fi
}

assert_contains '✅ OK     example.com. MX 10 mail.example.com.'
assert_contains '❌ missing mail.example.com. A 203.0.113.10'
assert_contains '✅ OK     example.com. TXT "v=spf1 mx -all"'
assert_contains '❌ missing _dmarc.example.com. TXT "v=DMARC1; p=none; rua=mailto:dmarc@example.com; adkim=s; aspf=s"'
assert_contains '✅ OK     default._domainkey.example.com. TXT "v=DKIM1; k=rsa; p=ABC123"'
assert_contains '❌ missing 203.0.113.10 -> mail.example.com'

printf 'wizard DNS record status rendering ok\n'
