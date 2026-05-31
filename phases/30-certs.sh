#!/usr/bin/env bash

render_template "$ROOT_DIR/templates/nginx/acme.conf.tmpl" /etc/nginx/sites-available/mailserver-acme.conf
run ln -sf /etc/nginx/sites-available/mailserver-acme.conf /etc/nginx/sites-enabled/mailserver-acme.conf
run nginx -t
reload_or_restart nginx

cert_path="/etc/letsencrypt/live/$MAIL_HOSTNAME/fullchain.pem"
if [[ ! -f "$cert_path" ]]; then
  certbot_args=(certonly --webroot -w /var/www/letsencrypt --non-interactive --agree-tos -m "$ADMIN_EMAIL" -d "$MAIL_HOSTNAME")
  [[ "$WEBMAIL_HOSTNAME" != "$MAIL_HOSTNAME" ]] && certbot_args+=(-d "$WEBMAIL_HOSTNAME")
  [[ "$DAV_HOSTNAME" != "$MAIL_HOSTNAME" && "$DAV_HOSTNAME" != "$WEBMAIL_HOSTNAME" ]] && certbot_args+=(-d "$DAV_HOSTNAME")
  [[ "${LETSENCRYPT_STAGING:-false}" == "true" ]] && certbot_args+=(--staging)
  run certbot "${certbot_args[@]}"
fi

write_file /etc/letsencrypt/renewal-hooks/deploy/reload-mailserver '#!/usr/bin/env bash
set -euo pipefail
systemctl reload postfix || true
systemctl reload dovecot || true
systemctl reload nginx || true
'
run chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-mailserver
mark_done certs
