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
- DNS control for `PRIMARY_DOMAIN`.
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
ADMIN_EMAIL=admin@example.com
WEBMAIL_HOSTNAME=mail.example.com
DAV_HOSTNAME=dav.example.com
```

- `MAIL_HOSTNAME`: SMTP, IMAP TLS certificate name, and MX target.
- `PRIMARY_DOMAIN`: domain that receives mail.
- `ADMIN_EMAIL`: Let's Encrypt registration and operational contact.
- `WEBMAIL_HOSTNAME`: Roundcube HTTPS hostname.
- `DAV_HOSTNAME`: Radicale CalDAV/CardDAV HTTPS hostname.

Using the same value for `MAIL_HOSTNAME` and `WEBMAIL_HOSTNAME` is supported.

### Public IP And System Identity

```bash
SERVER_PUBLIC_IPV4=203.0.113.10
SERVER_PUBLIC_IPV6=
TIMEZONE=Europe/Prague
```

- `SERVER_PUBLIC_IPV4`: public IPv4 that DNS A records must return.
- `SERVER_PUBLIC_IPV6`: optional public IPv6 for AAAA records.
- `TIMEZONE`: system timezone to set during install.

### Mail Storage

Defaults are usually fine:

```bash
VMAIL_UID=5000
VMAIL_GID=5000
VMAIL_ROOT=/var/vmail
MAIL_DB_PATH=/etc/mailserver/mail.sqlite
```

- `VMAIL_UID` and `VMAIL_GID`: virtual mail user/group IDs.
- `VMAIL_ROOT`: mailbox storage root.
- `MAIL_DB_PATH`: SQLite database for domains, users, and aliases.

### Roundcube Release Pin

Leave these values unchanged unless intentionally upgrading Roundcube:

```bash
ROUNDCUBE_VERSION=1.7.1
ROUNDCUBE_URL=https://github.com/roundcube/roundcubemail/releases/download/1.7.1/roundcubemail-1.7.1-complete.tar.gz
ROUNDCUBE_SHA256=1e0382bcefd627ab0b6285d3181ddfba5b444fdcf6d49f33f5ea15fbf97864ef
```

### Radicale Calendar Defaults

These values control calendar URLs and the default calendar created for each
mailbox. By default, Roundcube also installs a browser calendar plugin and uses
the local Radicale service as its CalDAV backend.

```bash
RADICALE_CALDAV_BASE_URL=https://dav.example.com/
RADICALE_DEFAULT_CALENDAR_NAME=default
RADICALE_DEFAULT_CALENDAR_DISPLAY_NAME=Default
```

### Roundcube Skin And Calendar

The installer defaults to the public Elastic2026 skin and enables the Roundcube
calendar plugin stack.

```bash
ROUNDCUBE_SKIN=elastic2026
ROUNDCUBE_SKIN_URL=https://github.com/zdehasek/Elastic2026/archive/refs/heads/main.zip
ROUNDCUBE_ENABLE_CALENDAR=true
ROUNDCUBE_CALDAV_SERVER=http://127.0.0.1:5232/
ROUNDCUBE_CALDAV_URL=http://127.0.0.1:5232/%u/%n/
ROUNDCUBE_DEFAULT_CALENDAR_NAME=default
```

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
- `ENABLE_RSPAMD`: spam filtering and milter integration.
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

Backups include mail configuration, Let's Encrypt data, Roundcube data, Radicale
collections, SQLite snapshots, and virtual mailboxes.

### Required Aliases And DKIM

```bash
POSTMASTER_ADDRESS=postmaster@example.com
ABUSE_ADDRESS=abuse@example.com
DKIM_SELECTOR=default
```

`POSTMASTER_ADDRESS` and `ABUSE_ADDRESS` must exist as mailboxes or aliases
after setup. `DKIM_SELECTOR` becomes the DNS name
`default._domainkey.example.com`.

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
server's public IPv4 networking settings. The reverse record must point from the
server IP back to `MAIL_HOSTNAME`:

```text
203.0.113.10 -> mail.example.com
```

For Hetzner, open the server, go to `Networking`, find the public IPv4 address,
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

## 11. 66c.dev Example

For the Alpha5 server:

```bash
MAIL_HOSTNAME=mail.66c.dev
PRIMARY_DOMAIN=66c.dev
ADMIN_EMAIL=admin@66c.dev
WEBMAIL_HOSTNAME=mail.66c.dev
DAV_HOSTNAME=dav.66c.dev
SERVER_PUBLIC_IPV4=46.225.176.230
SERVER_PUBLIC_IPV6=2a01:4f8:c0c:810b::1
TIMEZONE=Europe/Prague
VMAIL_UID=5000
VMAIL_GID=5000
VMAIL_ROOT=/var/vmail
MAIL_DB_PATH=/etc/mailserver/mail.sqlite
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
POSTMASTER_ADDRESS=postmaster@66c.dev
ABUSE_ADDRESS=abuse@66c.dev
DKIM_SELECTOR=default
PRIMARY_MAILBOX=alpha5@66c.dev
PRIMARY_MAILBOX_FULL_NAME=Alpha5
PRIMARY_MAILBOX_PASSWORD=
PRIMARY_MAILBOX_PASSWORD_FILE=/etc/mailserver/secrets/primary-mailbox-password
PRIMARY_ALIAS_ADDRESSES="postmaster@66c.dev abuse@66c.dev dmarc@66c.dev admin@66c.dev"
```

DNS:

```text
Type: A
Name: mail
Content: 46.225.176.230
Proxy: DNS only
TTL: Auto
```

```text
Type: AAAA
Name: mail
Content: 2a01:4f8:c0c:810b::1
Proxy: DNS only
TTL: Auto
```

```text
Type: A
Name: dav
Content: 46.225.176.230
Proxy: DNS only
TTL: Auto
```

```text
Type: AAAA
Name: dav
Content: 2a01:4f8:c0c:810b::1
Proxy: DNS only
TTL: Auto
```

```text
Type: MX
Name: @
Mail server: mail.66c.dev
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
Content: v=DMARC1; p=none; rua=mailto:dmarc@66c.dev; adkim=s; aspf=s
TTL: Auto
```

PTR/rDNS at the server/IP provider, not in Cloudflare DNS:

```text
46.225.176.230 -> mail.66c.dev
```
