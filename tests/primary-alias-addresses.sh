#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export MAILSERVER_SOURCE_ONLY=true
export NO_COLOR=1

# shellcheck source=../mailserver.sh disable=SC1091
source "$ROOT_DIR/mailserver.sh"

expected="postmaster@example.org abuse@example.org dmarc@example.org admin@example.org"
actual="$(primary_alias_addresses_for example.org)"

if [[ "$actual" != "$expected" ]]; then
  printf 'Expected primary aliases:\n%s\n\nActual:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

if [[ "$actual" == *"zdenek@example.org"* ]]; then
  printf 'Primary mailbox should not be listed as its own alias:\n%s\n' "$actual" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

config="$tmp_dir/config.env"
env -u MAILSERVER_SOURCE_ONLY "$ROOT_DIR/mailserver.sh" init --config "$config" --non-interactive --domain example.org --admin-email zdenek@example.org --public-ipv4 203.0.113.10 >/dev/null

admin_email="$(grep -E '^ADMIN_EMAIL=' "$config")"
primary_mailbox="$(grep -E '^PRIMARY_MAILBOX=' "$config")"
primary_aliases="$(grep -E '^PRIMARY_ALIAS_ADDRESSES=' "$config")"

if [[ "$admin_email" != "ADMIN_EMAIL=zdenek@example.org" || "$primary_mailbox" != "PRIMARY_MAILBOX=zdenek@example.org" ]]; then
  printf 'Unexpected primary config:\n%s\n%s\n' "$admin_email" "$primary_mailbox" >&2
  exit 1
fi

if [[ "$primary_aliases" != 'PRIMARY_ALIAS_ADDRESSES="postmaster@example.org abuse@example.org dmarc@example.org admin@example.org"' ]]; then
  printf 'Unexpected primary aliases in generated config:\n%s\n' "$primary_aliases" >&2
  exit 1
fi

printf 'primary alias addresses ok\n'
