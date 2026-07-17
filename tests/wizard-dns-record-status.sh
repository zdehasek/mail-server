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
❌ FAIL  default._domainkey.example.com TXT expected: default._domainkey.example.com. TXT "v=DKIM1; k=rsa; p=ABC123"; got: "v=DKIM1; k=rsa;\010p=ABC123"
❌ FAIL  203.0.113.10 PTR/rDNS expected: 203.0.113.10 -> mail.example.com; got: <none>
Summary: 4 failure(s), 0 warning(s)'

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
assert_contains '❌ different default._domainkey.example.com. TXT "v=DKIM1; k=rsa; p=ABC123"'
assert_contains '❌ missing 203.0.113.10 -> mail.example.com'

tls_records='Optional TLS policy DNS records:
mta-sts.example.com. A 203.0.113.10
_mta-sts.example.com. TXT "v=STSv1; id=1"
_smtp._tls.example.com. TXT "v=TLSRPTv1; rua=mailto:postmaster@example.com"
_25._tcp.mail.example.com. TLSA 3 1 1 ABC123'

tls_output='== TLS policy state for example.com ==
⚠ WARN  mta-sts.example.com A expected: mta-sts.example.com. A 203.0.113.10; got: <none>
⚠ WARN  _mta-sts.example.com TXT expected: _mta-sts.example.com. TXT "v=STSv1; id=1"; got: <none>
✅ OK    _smtp._tls.example.com. TXT "v=TLSRPTv1; rua=mailto:postmaster@example.com"
⚠ WARN  _25._tcp.mail.example.com TLSA expected: _25._tcp.mail.example.com. TLSA 3 1 1 ABC123; got: <none>'

tls_visible_output="$(wizard_records "$tls_records" "$tls_output")"
tls_visible_output="$(sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g' <<< "$tls_visible_output")"

if [[ "$tls_visible_output" != *'⚠ warn    mta-sts.example.com. A 203.0.113.10'* ]]; then
  printf 'Expected TLS A warning to be attached to the copy-pasteable record:\n%s\n' "$tls_visible_output" >&2
  exit 1
fi
if [[ "$tls_visible_output" != *'⚠ warn    _mta-sts.example.com. TXT "v=STSv1; id=1"'* ]]; then
  printf 'Expected MTA-STS TXT warning to be attached to the copy-pasteable record:\n%s\n' "$tls_visible_output" >&2
  exit 1
fi
if [[ "$tls_visible_output" != *'✅ OK     _smtp._tls.example.com. TXT "v=TLSRPTv1; rua=mailto:postmaster@example.com"'* ]]; then
  printf 'Expected TLSRPT OK to be attached to the copy-pasteable record:\n%s\n' "$tls_visible_output" >&2
  exit 1
fi
if [[ "$tls_visible_output" != *'⚠ warn    _25._tcp.mail.example.com. TLSA 3 1 1 ABC123'* ]]; then
  printf 'Expected TLSA warning to be attached to the copy-pasteable record:\n%s\n' "$tls_visible_output" >&2
  exit 1
fi

COLUMNS=40
long_dkim_record='default._domainkey.example.com. TXT "v=DKIM1; h=sha256; k=rsa; p=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"'
long_output="$(wizard_records "$long_dkim_record")"
long_visible_output="$(sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g' <<< "$long_output")"

if [[ "$long_visible_output" != *"$long_dkim_record"* ]]; then
  printf 'Expected long DKIM output to keep one copy-pasteable record line:\n%s\n\nActual output:\n%s\n' "$long_dkim_record" "$long_visible_output" >&2
  exit 1
fi

printf 'wizard DNS record status rendering ok\n'
