# Mail Server Setup Guide

This guide is the start-to-finish runbook for installing this mail server. It
covers both supported flows:

- Local setup: run the installer directly on the target server.
- SSH deploy: copy the repository to a remote server with `rsync`, then run the
  same local setup commands there.

The installer is intentionally not fully automatic. DNS, PTR/rDNS, provider SMTP
policy, and final deliverability tests must be handled outside the server.

## 1. Choose The Install Flow

Use local setup when you are already on the server:

```bash
git clone git@github.com:zdehasek/email-server.git
cd email-server
make init
```

Use SSH deploy when you are working from another machine and have SSH access to
the target server:

```bash
git clone git@github.com:zdehasek/email-server.git
cd email-server
make init
editor .env
make deploy HOST=app@example-server REMOTE_DIR=/tmp/mail-server
ssh app@example-server
cd /tmp/mail-server
```

Both flows converge here:

```bash
editor .env
make setup-dry-run
sudo make setup
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

## 3. Configure `.env`

Create `.env`:

```bash
make init
editor .env
```

The Makefile and installer both load this file.

### Deploy Settings

Used only by `make deploy`. Local setup ignores these values.

```bash
HOST=app@example-server
REMOTE_DIR=/tmp/mail-server
RSYNC=rsync
SSH=ssh
RSYNC_EXCLUDES=--exclude=.git/
```

- `HOST`: SSH destination for deploy, for example `app@203.0.113.10`.
- `REMOTE_DIR`: target directory on the remote server.
- `RSYNC`: rsync binary.
- `SSH`: ssh binary.
- `RSYNC_EXCLUDES`: extra rsync exclude arguments.

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

## 4. Publish DNS Before Installing

Let's Encrypt validation requires DNS to point at the target server before
`sudo make setup` runs.

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

Provider-side PTR/rDNS:

```text
203.0.113.10 -> mail.example.com
```

DKIM is generated during installation. Publish it after `sudo make setup` by
running `sudo make print-dns`.

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

## 6. Dry Run

Run:

```bash
make setup-dry-run
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
sudo make setup
```

This runs:

1. `doctor.sh`
2. `install.sh --assume-yes`
3. `verify.sh`
4. `scripts/print-dns.sh`

Managed files are backed up under `/var/backups/mailserver/<timestamp>/` before
they are overwritten.

## 8. Publish DKIM

After installation:

```bash
sudo make print-dns
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

## 9. Create Mailboxes And Aliases

Create the first mailbox:

```bash
sudo make add-user USER=alpha@example.com
```

Create required aliases:

```bash
sudo make add-alias SOURCE=postmaster@example.com DEST=alpha@example.com
sudo make add-alias SOURCE=abuse@example.com DEST=alpha@example.com
sudo make add-alias SOURCE=dmarc@example.com DEST=alpha@example.com
```

Install recurring backups:

```bash
sudo make install-backup-cron
```

## 10. Test

Local verification:

```bash
sudo make verify
```

Public ports from another machine:

```bash
nc -vz mail.example.com 25
nc -vz mail.example.com 587
nc -vz mail.example.com 993
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

PTR/rDNS:

```text
203.0.113.10 -> mail.example.org
```
