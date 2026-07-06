# Mail Server Setup Guide

This guide is the start-to-finish runbook for installing this mail server. It
covers the supported local setup flow: run the installer directly on the target
server.

The installer is intentionally not fully automatic. DNS, PTR/rDNS, provider SMTP
policy, and final deliverability tests must be handled outside the server.

## 1. Choose The Install Flow

Run on the target server:

```bash
git clone git@github.com:zdehasek/email-server.git
cd email-server
./mailserver.sh install-cli
mailserver init
mailserver setup-dry-run
sudo mailserver setup
```

Or bootstrap a checkout from a hosted copy of the CLI:

```bash
curl -fsSL https://raw.githubusercontent.com/zdehasek/email-server/master/mailserver.sh | sudo bash
mailserver setup-dry-run
sudo mailserver setup
```

The curl-pipe path only creates or reuses a local git checkout and runs the
command there. With no curl-pipe command argument, it runs `init` by default.
Override the defaults with `MAILSERVER_REPO_URL`, `MAILSERVER_INSTALL_DIR`, or
`MAILSERVER_REF`. It keeps the checkout under `MAILSERVER_INSTALL_DIR`,
`/opt/mailserver` by default, and tries to install the `mailserver` command into
`/usr/local/bin` when permissions allow it.

To use your own URL, publish the raw `mailserver.sh` file somewhere reachable
over HTTPS. For GitHub, use this shape:

```text
https://raw.githubusercontent.com/<owner>/<repo>/<branch>/mailserver.sh
```

For a custom domain, point Nginx/Caddy/static hosting at the raw file and verify
the URL before piping it into Bash:

```bash
curl -fsSL https://your-domain.example/mailserver.sh | head
```

If the raw script should clone a fork or private mirror, pass its git URL into
the bootstrap command:

```bash
curl -fsSL https://your-domain.example/mailserver.sh | sudo MAILSERVER_REPO_URL=https://github.com/<owner>/<repo>.git bash
```

## 2. Confirm The Target Server

Run on the target server:

```bash
hostname -f
curl -4 https://api.ipify.org && printf '\n'
curl -6 https://api64.ipify.org && printf '\n'
cat /etc/os-release
sudo ufw status verbose || true
sudo ss -ltnp
```

Requirements:

- Ubuntu 26.04.
- `sudo` access.
- Static public IPv4.
- Provider allows inbound and outbound TCP/25.
- Ports available from the internet: `25`, `80`, `443`, `587`, `993`.
- DNS control for `PRIMARY_DOMAIN` and every configured `SECONDARY_DOMAINS` entry.
- Provider control for PTR/rDNS.

If an existing web server already uses `80`/`443`, keep it running only if it is
Nginx and separate `server_name` blocks can be added for the mail hostnames.
The installer manages Nginx vhosts for webmail and DAV.

## 3. Create `~/.email-server/config.env`

Create the default config with the interactive init wizard:

```bash
mailserver init
```

`mailserver` loads this file automatically. You can also pass
`--config /path/to/config.env` to any subcommand, or set `CONFIG` or
`ENV_FILE`. When a command runs through `sudo`, the sudo user's home is used so
`sudo mailserver setup` reads the same default config created by
`mailserver init`.

For unattended setup, pass the important values directly:

```bash
mailserver init \
  --domain example.com \
  --admin-email admin@example.com \
  --mail-hostname mail.example.com \
  --webmail-hostname mail.example.com \
  --dav-hostname dav.example.com \
  --public-ipv4 203.0.113.10 \
  --timezone Europe/Prague
```

Manual editing of `~/.email-server/config.env` is still possible for advanced
changes, but it is not the normal install path.

### Domain And Hostnames

```bash
MAIL_HOSTNAME=mail.example.com
PRIMARY_DOMAIN=example.com
SECONDARY_DOMAINS=
ADMIN_EMAIL=admin@example.com
WEBMAIL_HOSTNAME=mail.example.com
DAV_HOSTNAME=dav.example.com
```

- `MAIL_HOSTNAME`: SMTP, IMAP TLS certificate name, and MX target.
- `PRIMARY_DOMAIN`: domain that receives mail.
- `SECONDARY_DOMAINS`: optional space-separated extra domains served by the same mail host, for example `example.org example.net`.
- `ADMIN_EMAIL`: Let's Encrypt registration and operational contact.
- `WEBMAIL_HOSTNAME`: SOGo HTTPS hostname.
- `DAV_HOSTNAME`: optional CalDAV/CardDAV hostname; it can be the same as `WEBMAIL_HOSTNAME`.

Using the same value for `MAIL_HOSTNAME` and `WEBMAIL_HOSTNAME` is supported.

### Public IP And System Identity

```bash
SERVER_PUBLIC_IPV4=203.0.113.10
SERVER_PUBLIC_IPV6=
TIMEZONE=Europe/Prague
```

- `SERVER_PUBLIC_IPV4`: public IPv4 that DNS A records must return.
- `SERVER_PUBLIC_IPV6`: optional public IPv6 for AAAA records and IPv6 PTR/rDNS checks.
- `TIMEZONE`: system timezone to set during install.

### Mail Storage

Defaults are usually fine:

```bash
VMAIL_UID=5000
VMAIL_GID=5000
VMAIL_ROOT=/var/vmail
MAIL_DB_PATH=/etc/mailserver/mail.sqlite
MAIL_DB_NAME=mailserver
MAIL_DB_USER=mailserver
MAIL_DB_HOST=127.0.0.1
MAIL_DB_PASSWORD_FILE=/etc/mailserver/secrets/postgresql-mailserver-password
```

- `VMAIL_UID` and `VMAIL_GID`: virtual mail user/group IDs.
- `VMAIL_ROOT`: mailbox storage root.
- `MAIL_DB_PATH`: optional legacy SQLite database path used only for one-time migration during upgrades.
- `MAIL_DB_NAME`, `MAIL_DB_USER`, `MAIL_DB_HOST`, and `MAIL_DB_PASSWORD_FILE`: PostgreSQL connection used by Postfix, Dovecot, and SOGo.

### Install Features

```bash
LETSENCRYPT_STAGING=false
ENABLE_UFW=true
UFW_RESET_RULES=false
ENABLE_FAIL2BAN=true
ENABLE_SSH_HARDENING=false
ENABLE_RSPAMD=true
ENABLE_CLAMAV=false
```

- `LETSENCRYPT_STAGING`: use `true` for certificate testing only.
- `ENABLE_UFW`: manage firewall rules.
- `UFW_RESET_RULES`: set `false` on a server with existing firewall rules.
- `ENABLE_FAIL2BAN`: install mail-oriented Fail2ban jail config.
- `ENABLE_SSH_HARDENING`: keep `false` until SSH users are verified.
- `ENABLE_RSPAMD`: spam filtering and milter integration. If set to `false`,
  Postfix is rendered without the Rspamd milter and mail continues without this
  spam-filtering layer.
- `ENABLE_CLAMAV`: disabled by default because it needs more RAM.

### SSH Hardening

Used only when `ENABLE_SSH_HARDENING=true`.

```bash
SSH_PORT=22
SSH_ALLOW_USERS=app
```

Set `SSH_ALLOW_USERS` to a key-enabled admin user before enabling SSH
hardening. The installer refuses risky hardening when it cannot verify a safe
user.

### Backups

```bash
BACKUP_DIR=/var/backups/mailserver-data
BACKUP_RETENTION_DAYS=14
BACKUP_CRON_SCHEDULE="17 3 * * *"
```

Backups include mail configuration, Let's Encrypt data, a PostgreSQL dump, SOGo
configuration, and virtual mailboxes.

### Required Aliases And DKIM

```bash
POSTMASTER_ADDRESS=postmaster@example.com
ABUSE_ADDRESS=abuse@example.com
DKIM_SELECTOR=default
```

`POSTMASTER_ADDRESS` and `ABUSE_ADDRESS` must exist as mailboxes or aliases
after setup. `DKIM_SELECTOR` becomes the DNS name
`default._domainkey.example.com`. DKIM keys and DNS records are generated for
`PRIMARY_DOMAIN` and every domain listed in `SECONDARY_DOMAINS`.

### Primary Mailbox And Default Aliases

The setup flow can create one primary mailbox and point the required operational
aliases to it.

```bash
PRIMARY_MAILBOX=admin@example.com
PRIMARY_MAILBOX_FULL_NAME=Mail Admin
PRIMARY_MAILBOX_PASSWORD=
PRIMARY_MAILBOX_PASSWORD_FILE=/etc/mailserver/secrets/primary-mailbox-password
PRIMARY_ALIAS_ADDRESSES="postmaster@example.com abuse@example.com dmarc@example.com admin@example.com"
```

- `PRIMARY_MAILBOX`: mailbox created automatically during `sudo mailserver setup`.
- `PRIMARY_MAILBOX_FULL_NAME`: display name stored for the mailbox.
- `PRIMARY_MAILBOX_PASSWORD`: optional explicit password. Leave empty to
  generate one.
- `PRIMARY_MAILBOX_PASSWORD_FILE`: root-only file where the generated password is
  stored.
- `PRIMARY_ALIAS_ADDRESSES`: space-separated aliases pointing to
  `PRIMARY_MAILBOX`.

If `PRIMARY_MAILBOX` is empty, setup skips this step. If the mailbox already
exists, setup updates the password hash and keeps it active. If an alias already
exists, setup leaves it in place.

Use `sudo mailserver add-domain --domain example.net` to activate another domain
after setup. It seeds the domain database, refreshes DKIM tables, reloads mail
services, and prints the DNS records to publish.

## 4. Publish DNS Before Installing

Let's Encrypt validation requires DNS to point at the target server before
`sudo mailserver setup` runs.

Use DNS-only records for mail hostnames when using Cloudflare. Do not proxy SMTP
or IMAP hostnames through Cloudflare.

```text
Type: A
Name: mail
Content: 203.0.113.10
Proxy: DNS only
TTL: Auto
```

```text
Type: A
Name: dav
Content: 203.0.113.10
Proxy: DNS only
TTL: Auto
```

If IPv6 is configured:

```text
Type: AAAA
Name: mail
Content: 2001:db8::10
Proxy: DNS only
TTL: Auto
```

```text
Type: AAAA
Name: dav
Content: 2001:db8::10
Proxy: DNS only
TTL: Auto
```

Mail routing:

```text
Type: MX
Name: @
Mail server: mail.example.com
Priority: 10
TTL: Auto
```

Sender authentication:

```text
Type: TXT
Name: @
Content: v=spf1 mx -all
TTL: Auto
```

```text
Type: TXT
Name: _dmarc
Content: v=DMARC1; p=none; rua=mailto:dmarc@example.com; adkim=s; aspf=s
TTL: Auto
```

Provider-side PTR/rDNS is not a DNS-zone record. Set it at the provider that
owns the server IP address, for example in Hetzner Cloud Console under the
server's public networking settings. Each public mail server IP reverse record
must point back to `MAIL_HOSTNAME`:

```text
203.0.113.10 -> mail.example.com
2001:db8::10 -> mail.example.com
```

For Hetzner, open the server, go to `Networking`, find the public IP address,
edit `Reverse DNS` / `rDNS`, and set it to `mail.example.com`.

DKIM is generated during installation. Publish it after `sudo mailserver setup`
by running `sudo mailserver print-dns`. For additional domains, run
`sudo mailserver add-domain --domain example.net`, then
`sudo mailserver print-dns --domain example.net`. `add-domain` creates the
standard `postmaster`, `abuse`, and `dmarc` aliases to `ADMIN_EMAIL` unless
you pass `--alias-dest` or `--no-default-aliases`.

## 5. Wait For DNS

Verify from the target server:

```bash
dig +short mail.example.com A
dig +short dav.example.com A
dig +short MX example.com
dig +short TXT example.com
dig +short TXT _dmarc.example.com
```

`mail.example.com` and `dav.example.com` must return `SERVER_PUBLIC_IPV4` before
continuing.

For a complete check against the configured `~/.email-server/config.env`, run:

```bash
mailserver check
```

This runs DNS, SSL/TLS, and service checks. To inspect only DNS, run
`mailserver dns-state`.

## 6. Dry Run

Run:

```bash
mailserver setup-dry-run
```

Do not continue until the dry run finishes without errors. Read warnings before
continuing. Common blockers:

- DNS still points to another IP.
- Hostname differs from `MAIL_HOSTNAME`.
- Required ports are already used by a conflicting service.
- Less than 1 GB RAM.
- Low disk space.

## 7. Install

Run on the target server:

```bash
sudo mailserver setup
```

This runs:

1. `mailserver doctor`
2. `mailserver install`
3. `mailserver verify`
4. `mailserver print-dns`

Managed files are backed up under `/var/backups/mailserver/<timestamp>/` before
they are overwritten.

## 8. Publish DKIM

After installation:

```bash
sudo mailserver print-dns
```

Copy the generated DKIM TXT record:

```text
Type: TXT
Name: default._domainkey
Content: <generated DKIM value>
TTL: Auto
```

Keep DMARC at `p=none` until outbound delivery tests are clean. Later move to
`p=quarantine`, then `p=reject`.

After publishing DKIM, verify the live DNS state again:

```bash
mailserver dns-state
```

## 9. Confirm Primary Mailbox And Aliases

If `PRIMARY_MAILBOX` is set, `sudo mailserver setup` creates the mailbox and
aliases automatically. To run only that step again:

```bash
sudo mailserver setup-primary-mailbox
```

If the password was generated, read it from the root-only password file:

```bash
sudo cat /etc/mailserver/secrets/primary-mailbox-password
```

Additional mailboxes can still be created manually:

```bash
sudo mailserver add-user --user user@example.com
```

Additional domains must be configured before creating mailboxes or aliases for
them:

```bash
sudo mailserver add-domain --domain example.org
sudo mailserver add-user --user user@example.org
```

Install recurring backups:

```bash
sudo mailserver install-backup-cron
```

## 10. Test

Run the built-in checks:

```bash
sudo mailserver verify
mailserver check
```

The combined `check` command runs:

```bash
mailserver dns-state
mailserver check-ssl
mailserver service-state
```

Webmail:

```text
https://mail.example.com/
```

DAV:

```text
https://dav.example.com/user@example.com/
```

Send outbound tests to Gmail, Seznam, and another independent mailbox. Inspect
authentication headers for SPF, DKIM, and DMARC pass results.

## 11. example.org Example

For the Alpha5 server:

```bash
MAIL_HOSTNAME=mail.example.org
PRIMARY_DOMAIN=example.org
ADMIN_EMAIL=admin@example.org
WEBMAIL_HOSTNAME=mail.example.org
DAV_HOSTNAME=dav.example.org
SERVER_PUBLIC_IPV4=203.0.113.10
SERVER_PUBLIC_IPV6=2001:db8::10
TIMEZONE=Europe/Prague
VMAIL_UID=5000
VMAIL_GID=5000
VMAIL_ROOT=/var/vmail
MAIL_DB_PATH=/etc/mailserver/mail.sqlite
MAIL_DB_NAME=mailserver
MAIL_DB_USER=mailserver
MAIL_DB_HOST=127.0.0.1
MAIL_DB_PASSWORD_FILE=/etc/mailserver/secrets/postgresql-mailserver-password
LETSENCRYPT_STAGING=false
ENABLE_UFW=true
UFW_RESET_RULES=false
ENABLE_FAIL2BAN=true
ENABLE_SSH_HARDENING=false
ENABLE_RSPAMD=true
ENABLE_CLAMAV=false
SSH_PORT=22
SSH_ALLOW_USERS=openclaw
BACKUP_DIR=/var/backups/mailserver-data
BACKUP_RETENTION_DAYS=14
BACKUP_CRON_SCHEDULE="17 3 * * *"
POSTMASTER_ADDRESS=postmaster@example.org
ABUSE_ADDRESS=abuse@example.org
DKIM_SELECTOR=default
PRIMARY_MAILBOX=admin@example.org
PRIMARY_MAILBOX_FULL_NAME=Alpha5
PRIMARY_MAILBOX_PASSWORD=
PRIMARY_MAILBOX_PASSWORD_FILE=/etc/mailserver/secrets/primary-mailbox-password
PRIMARY_ALIAS_ADDRESSES="postmaster@example.org abuse@example.org dmarc@example.org admin@example.org"
```

DNS:

```text
Type: A
Name: mail
Content: 203.0.113.10
Proxy: DNS only
TTL: Auto
```

```text
Type: AAAA
Name: mail
Content: 2001:db8::10
Proxy: DNS only
TTL: Auto
```

```text
Type: A
Name: dav
Content: 203.0.113.10
Proxy: DNS only
TTL: Auto
```

```text
Type: AAAA
Name: dav
Content: 2001:db8::10
Proxy: DNS only
TTL: Auto
```

```text
Type: MX
Name: @
Mail server: mail.example.org
Priority: 10
TTL: Auto
```

```text
Type: TXT
Name: @
Content: v=spf1 mx -all
TTL: Auto
```

```text
Type: TXT
Name: _dmarc
Content: v=DMARC1; p=none; rua=mailto:dmarc@example.org; adkim=s; aspf=s
TTL: Auto
```

PTR/rDNS at the server/IP provider, not in Cloudflare DNS:

```text
203.0.113.10 -> mail.example.org
2001:db8::10 -> mail.example.org
```
