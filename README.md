# Ubuntu Mail Server Installer

Non-Docker Bash installer for a production-oriented Ubuntu 26.04 mail server.

Default stack:

- Postfix for SMTP inbound and authenticated submission.
- Dovecot for IMAPS, LMTP delivery, authentication, and Sieve.
- SQLite for virtual domains, users, and aliases.
- Roundcube for stable browser webmail.
- Radicale for contacts, calendars, CalDAV, and CardDAV.
- Nginx as HTTPS reverse proxy.
- Let's Encrypt certificates via Certbot webroot challenge.
- OpenDKIM, OpenDMARC, SPF policy checks, and Rspamd.
- Fail2ban and cautious UFW hardening.

## Quick Start

```bash
make init
editor mail.env
make doctor
make dry-run
sudo make install
sudo make add-user USER=user@example.com
sudo make print-dns
sudo make verify
```

Deploy to a remote host:

```bash
make deploy HOST=app@46.224.197.110 REMOTE_DIR=/tmp/mail-server
```

Do not run this on an existing mail server without reading `docs/prerequisites.md` and taking backups. The installer backs up managed files before overwriting them, but it is designed for a fresh Ubuntu 26.04 host.

## Manual Requirements

Email deliverability cannot be made fully automatic. Production use requires DNS and provider-side setup:

- DNS control for the domain.
- Static public IPv4 address.
- Provider allows inbound and outbound TCP/25.
- PTR/rDNS for the server IP points to `MAIL_HOSTNAME`.
- `A`/optional `AAAA`, `MX`, SPF, DKIM, and DMARC records.
- Public ports open: `25`, `80`, `443`, `587`, `993`.

See `docs/dns.md` for exact records.

## Why Roundcube And Radicale

SOGo is capable but overbuilt for a small self-hosted mail server. This installer uses smaller, stable single-purpose components: Roundcube for webmail and Radicale for contacts/calendar sync. It intentionally does not install a browser calendar UI by default; use native CalDAV/CardDAV clients unless a heavier groupware stack is explicitly needed.

See `docs/webmail-options.md` for the comparison.

## Safety

- `doctor.sh` is read-only.
- `install.sh --dry-run` prints intended changes without applying them.
- Managed files are backed up under `/var/backups/mailserver/<timestamp>/`.
- Mailboxes are never deleted by these scripts.
- UFW is not enabled unless SSH safety checks pass.
