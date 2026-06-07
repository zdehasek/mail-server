# Local Server Setup

This guide is for installing the mail server from the target server itself. It
does not require SSH or `make deploy`. Use the SSH/rsync deploy flow only when
you want to push this repository from another machine.

## 1. Confirm The Target Server

Run these commands on the server that will host mail:

```bash
hostname -f
curl -4 https://api.ipify.org && printf '\n'
curl -6 https://api64.ipify.org && printf '\n'
cat /etc/os-release
```

Requirements:

- Ubuntu 26.04.
- `sudo` access.
- Public IPv4.
- Provider allows inbound and outbound TCP/25.
- Public ports will be available: `25`, `80`, `443`, `587`, `993`.

If an existing web server already uses `80`/`443`, keep it running only if it is
Nginx and separate `server_name` blocks can be added for the mail hostnames.

## 2. Clone And Initialize

Run on the target server:

```bash
git clone git@github.com:zdehasek/email-server.git
cd email-server
make init
```

Edit `.env`:

```bash
nano .env
```

Minimum values to set:

```bash
MAIL_HOSTNAME=mail.example.com
PRIMARY_DOMAIN=example.com
ADMIN_EMAIL=admin@example.com
WEBMAIL_HOSTNAME=mail.example.com
DAV_HOSTNAME=dav.example.com
SERVER_PUBLIC_IPV4=203.0.113.10
SERVER_PUBLIC_IPV6=
TIMEZONE=Europe/Prague
UFW_RESET_RULES=false
ENABLE_SSH_HARDENING=false
POSTMASTER_ADDRESS=postmaster@example.com
ABUSE_ADDRESS=abuse@example.com
DKIM_SELECTOR=default
```

Use `UFW_RESET_RULES=false` on a server that already has firewall rules. Use
`ENABLE_SSH_HARDENING=false` unless you have already verified a key-enabled
admin user.

## 3. Publish DNS Before Installing

Let's Encrypt validation requires DNS to point at this server before
`sudo make setup` runs.

Create these records:

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

If the server has IPv6:

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

Mail routing and authentication:

```text
Type: MX
Name: @
Mail server: mail.example.com
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
Content: v=DMARC1; p=none; rua=mailto:dmarc@example.com; adkim=s; aspf=s
TTL: Auto
```

Set provider-side PTR/rDNS:

```text
203.0.113.10 -> mail.example.com
```

DKIM is generated during installation and is published later.

## 4. Wait For DNS

Verify from the target server:

```bash
dig +short mail.example.com A
dig +short dav.example.com A
dig +short MX example.com
```

The `mail.example.com` and `dav.example.com` A records must return the server's
public IPv4 before continuing.

## 5. Dry Run

Run:

```bash
make setup-dry-run
```

Do not continue until the dry run finishes without errors. Warnings can be
acceptable, but read them carefully. Common blockers:

- DNS still points to another IP.
- Hostname is different from `MAIL_HOSTNAME`.
- Required ports are already used by a conflicting service.
- Less than 1 GB RAM or very low disk space.

## 6. Install

Run:

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

## 7. Publish DKIM

After installation, print final DNS:

```bash
sudo make print-dns
```

Copy the generated DKIM TXT record:

```text
Name: default._domainkey
Type: TXT
Content: <generated DKIM value>
```

Keep DMARC at `p=none` until outbound delivery to Gmail, Seznam, and other test
recipients works reliably.

## 8. Create The First Mailbox

Create a mailbox:

```bash
sudo make add-user USER=alpha@example.com
```

Create required aliases to that mailbox:

```bash
sudo make add-alias SOURCE=postmaster@example.com DEST=alpha@example.com
sudo make add-alias SOURCE=abuse@example.com DEST=alpha@example.com
sudo make add-alias SOURCE=dmarc@example.com DEST=alpha@example.com
```

Install recurring backups:

```bash
sudo make install-backup-cron
```

## 9. Test

Run local verification:

```bash
sudo make verify
```

Check public ports from another machine:

```bash
nc -vz mail.example.com 25
nc -vz mail.example.com 587
nc -vz mail.example.com 993
```

Open webmail:

```text
https://mail.example.com/
```

Test IMAP and SMTP with the mailbox created in step 8. Then send outbound tests
to Gmail and Seznam and inspect spam placement and authentication headers.

## 66c.dev Example

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
UFW_RESET_RULES=false
ENABLE_SSH_HARDENING=false
POSTMASTER_ADDRESS=postmaster@66c.dev
ABUSE_ADDRESS=abuse@66c.dev
DKIM_SELECTOR=default
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

PTR/rDNS:

```text
46.225.176.230 -> mail.66c.dev
```
