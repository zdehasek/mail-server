#!/usr/bin/env bash

sync_dkim_domains() {
  local domain dkim_dir key_table="" signing_table="" trusted_hosts
  trusted_hosts=$'127.0.0.1\n::1\nlocalhost\n'"$MAIL_HOSTNAME"$'\n'

  while IFS= read -r domain; do
    dkim_dir="$DKIM_ROOT/$domain"
    run mkdir -p "$dkim_dir"
    if [[ "$DRY_RUN" != "true" && ! -f "$dkim_dir/$DKIM_SELECTOR.private" ]]; then
      opendkim-genkey -b 2048 -d "$domain" -s "$DKIM_SELECTOR" -D "$dkim_dir"
    fi
    if [[ "$DRY_RUN" != "true" && -f "$dkim_dir/$DKIM_SELECTOR.private" ]]; then
      chown -R opendkim:opendkim "$dkim_dir"
      chmod 0600 "$dkim_dir/$DKIM_SELECTOR.private"
    fi

    key_table+="$DKIM_SELECTOR._domainkey.$domain $domain:$DKIM_SELECTOR:$dkim_dir/$DKIM_SELECTOR.private"$'\n'
    signing_table+="*@$domain $DKIM_SELECTOR._domainkey.$domain"$'\n'
    trusted_hosts+="$domain"$'\n'
  done < <(mail_domains)

  write_file /etc/opendkim/signing.table "$MANAGED_HEADER
$signing_table"
  write_file /etc/opendkim/key.table "$MANAGED_HEADER
$key_table"
  write_file /etc/opendkim/trusted.hosts "$MANAGED_HEADER
$trusted_hosts"
}
