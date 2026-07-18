# Ubuntu Mail Server Installer

Non-Docker Bash installer for a production-oriented Ubuntu 26.04 mail server.

Default stack:

- Postfix for SMTP inbound and authenticated submission.
- Dovecot for IMAPS, LMTP delivery, authentication, and Sieve.
- PostgreSQL for virtual domains, users, aliases, and SOGo groupware data.
- SOGo for browser webmail, contacts, calendars, CalDAV/CardDAV, and ActiveSync.
- Nginx as HTTPS reverse proxy.
- Let's Encrypt certificates via Certbot webroot challenge.
- OpenDKIM, OpenDMARC, SPF policy checks, and Rspamd.
- Fail2ban and cautious UFW hardening.

## Quick Start

For the complete step-by-step setup guide, including local installation,
`~/.email-server/config.env`, DNS, DKIM, mailboxes, and tests, follow
[`docs/setup-guide.md`](docs/setup-guide.md).

```bash
git clone git@github.com:zdehasek/mail-server.git
cd mail-server
./mailserver.sh install-cli
mailserver init
```

Run these commands on the target server. Remote deployment is not a supported
interface. By default, `mailserver init` creates
`~/.email-server/config.env`, walks through DNS records, waits until they verify,
installs the stack, verifies services, and then walks through DKIM DNS. The
guided setup keeps package, Certbot, and service output in a timestamped log so
the terminal stays focused on the current step and the next action. Use
`mailserver init --config-only` when you only want to create the config and run
the lower-level commands manually. All commands use that file unless
`--config PATH`, `CONFIG=PATH`, or `ENV_FILE=PATH` is set. When a command is run
with `sudo`, the sudo user's home is used for the default config path.

You can also bootstrap the checkout on the target server with a hosted copy of
`mailserver.sh`:

```bash
curl -fsSL https://raw.githubusercontent.com/zdehasek/mail-server/master/mailserver.sh | sudo bash
mailserver setup-dry-run
sudo mailserver setup
```

Set `MAILSERVER_REPO_URL`, `MAILSERVER_INSTALL_DIR`, or `MAILSERVER_REF` before
`bash` to override the git source, install path, or branch/tag. Curl-pipe
bootstrap keeps the checkout under `MAILSERVER_INSTALL_DIR`, `/opt/mailserver`
by default, and tries to install `/usr/local/bin/mailserver` when permissions
allow it. With no curl-pipe command argument, it runs `init` by default. If PATH
installation fails, run `/opt/mailserver/mailserver.sh install-cli` later.

To make the curl URL work for your own fork, commit `mailserver.sh`, push it to
GitHub, and use the raw file URL:

```text
https://raw.githubusercontent.com/<owner>/<repo>/<branch>/mailserver.sh
```

For a custom domain, serve the same raw `mailserver.sh` file over HTTPS and make
sure this succeeds on a clean server:

```bash
curl -fsSL https://your-domain.example/mailserver.sh | head
```

The piped script only bootstraps a local git checkout. Set
`MAILSERVER_REPO_URL=https://github.com/<owner>/<repo>.git` when the hosted
`mailserver.sh` should clone a fork instead of the default repository.

```bash
mailserver update
```

`update` fast-forwards the checked-out installer from its git remote. If you run
the CLI via a curl-pipe one-liner, it first reuses or creates the local checkout
and then runs the update there.

```bash
mailserver reset-setup
```

`reset-setup` moves the local setup config aside so the wizard can be started
again. It does not uninstall packages, services, domains, users, or mailbox
data.

Do not run this on an existing mail server without reading `docs/prerequisites.md` and taking backups. The installer backs up managed files before overwriting them, but it is designed for a fresh Ubuntu 26.04 host.

## Manual Requirements

Email deliverability cannot be made fully automatic. Production use requires DNS and provider-side setup:

- DNS control for each served domain.
- Static public IPv4 address.
- Provider allows inbound and outbound TCP/25.
- PTR/rDNS for each public mail server IP points to `MAIL_HOSTNAME`. Configure
  this at the IP/server provider, not as a Cloudflare DNS record.
- `A`/optional `AAAA`, `MX`, SPF, DKIM, and DMARC records.
- Public ports open: `25`, `80`, `443`, `587`, `993`.

See `docs/dns.md` for exact records.

## SOGo Groupware

The web layer is SOGo. It uses the local Dovecot IMAP service for mail access,
Postfix submission for outbound mail, and PostgreSQL for users, calendars,
contacts, sessions, and profile data.

## Safety

- `mailserver doctor` is read-only unless explicitly run with `--fix`.
- `mailserver doctor --fix` can repair local UFW, service, and managed webmail config drift.
- `install.sh --dry-run` prints intended changes without applying them.
- Managed files are backed up under `/var/backups/mailserver/<timestamp>/`.
- `sudo mailserver backup` creates a mail server data backup.
- `sudo mailserver remove --purge` is destructive. It requires typing a full
  confirmation sentence and removes services, mail data, databases, generated
  config, secrets, and mailserver backups. Before dropping PostgreSQL, it writes
  a purge safety dump under `/var/backups/mailserver-purge/`.
- `sudo mailserver install-backup-cron` installs a recurring backup job.
- Mailboxes are never deleted by routine mailbox/domain commands.
- UFW defaults to deny incoming and only allows SSH, SMTP, HTTP/HTTPS, submission, and IMAPS.
- SSH hardening is skipped unless a key-enabled allowed user is known.
