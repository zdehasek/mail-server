# Operations

Create a mailbox:

```bash
sudo mailserver users add --user user@example.com
```

List configured mail domains:

```bash
sudo mailserver domains ls
```

Change the configured primary mail domain:

```bash
mailserver domains set --domain example.net
```

This updates `PRIMARY_DOMAIN`, required operational aliases, `ADMIN_EMAIL` when
it used the old primary domain, and the configured primary mailbox. It keeps a
timestamped `.bak` copy beside the config file. Hostnames are not changed unless
you pass them explicitly:

```bash
mailserver domains set --domain example.net \
  --mail-hostname mail.example.net \
  --webmail-hostname mail.example.net \
  --dav-hostname dav.example.net
```

After changing the primary domain, run:

```bash
mailserver doctor
sudo mailserver setup-primary-mailbox
sudo mailserver print-dns
```

Activate another mail domain in the virtual mailbox database:

```bash
sudo mailserver domains add --domain example.net
```

This also generates a DKIM key under `/etc/mailserver/dkim/example.net/`,
refreshes the OpenDKIM signing maps, reloads OpenDKIM, and creates
`postmaster@example.net`, `abuse@example.net`, and `dmarc@example.net` aliases
to `ADMIN_EMAIL`. Use `--alias-dest admin@example.com` to choose a different
destination, or `--no-default-aliases` to skip them.

Print and publish the DNS records for that domain:

```bash
sudo mailserver print-dns --domain example.net
mailserver dns-state --domain example.net
```

Then add mailboxes or aliases on that domain:

```bash
sudo mailserver users add --user user@example.net
sudo mailserver aliases add --source postmaster@example.net --dest admin@example.com
```

Deactivate a non-primary domain, including its active mailboxes and aliases:

```bash
sudo mailserver domains rm --domain example.net
```

This does not delete maildirs from disk. DNS and DKIM records for non-primary
domains are domain-specific; use `--domain` when printing or checking them.

## Purge the server

Use this only when you want to wipe the local mailserver install and start over
from defaults:

```bash
sudo mailserver remove --purge
```

The command prints a red destructive-action warning and requires typing the full
confirmation sentence shown on screen. It stops and disables mail services,
drops the configured PostgreSQL database and role, deletes mailbox data,
generated config, `/etc/mailserver` secrets/state, generated TLS material, and
mailserver backups, resets UFW, and purges installed mail/webmail packages.

Create or refresh the configured primary mailbox and operational aliases:

```bash
sudo mailserver setup-primary-mailbox
```

If the primary mailbox password was generated during setup, read it with:

```bash
sudo cat /etc/mailserver/secrets/primary-mailbox-password
```

Create an alias:

```bash
sudo mailserver aliases add --source postmaster@example.com --dest admin@example.com
```

List active aliases and forwards:

```bash
sudo mailserver aliases ls
sudo mailserver aliases ls --domain example.com
sudo mailserver forwards ls
sudo mailserver forwards ls --domain example.com
```

The `source_is_mailbox` column is `yes` when the source address is an active
mailbox, which means the row behaves as a mailbox forward.

Redirect an address to exactly one active destination, deactivating any other
active alias rows for the same source:

```bash
sudo mailserver aliases set --source abuse@example.com --dest admin@example.net
```

Redirect operational addresses to one mailbox:

```bash
sudo mailserver aliases set --source postmaster@example.com --dest admin@example.net
sudo mailserver aliases set --source abuse@example.com --dest admin@example.net
sudo mailserver aliases set --source dmarc@example.com --dest admin@example.net
```

Forward an address with mailbox-source protection:

```bash
sudo mailserver forwards add --source ops@example.com --dest admin@example.net
```

If the source is an active mailbox, forwarding redirects delivery away from the
local mailbox. The command refuses that case unless you make the behavior
explicit:

```bash
sudo mailserver forwards add --source admin@example.com --dest admin@example.net --allow-mailbox-source
```

Change a password:

```bash
sudo mailserver users passwd --user user@example.com
```

Create an on-demand backup:

```bash
sudo mailserver backup
```

List, validate, inspect, or safely extract a backup:

```bash
sudo mailserver restore --list
sudo mailserver restore --validate /var/backups/mailserver-data/mailserver-YYYYmmddTHHMMSSZ.tar.gz
sudo mailserver restore --inspect /var/backups/mailserver-data/mailserver-YYYYmmddTHHMMSSZ.tar.gz
sudo mailserver restore --extract /var/backups/mailserver-data/mailserver-YYYYmmddTHHMMSSZ.tar.gz --target /root/mailserver-restore-review
```

`restore --extract` is intentionally non-destructive. It unpacks into a staging
directory so an operator can review PostgreSQL dumps, config files, certificates,
and maildirs before copying anything back into production paths.

Install the recurring backup cron job:

```bash
sudo mailserver install-backup-cron
```

Useful logs:

```bash
journalctl -u postfix
journalctl -u dovecot
journalctl -u sogo
journalctl -u rspamd
tail -f /var/log/mail.log
```

Webmail URL:

```text
https://mail.example.com/
```

SOGo CalDAV/CardDAV base URL:

```text
https://mail.example.com/SOGo/dav/user@example.com/
```

Print complete manual setup values for Apple Mail, Apple Calendar, Thunderbird
Mail, and Thunderbird Calendar:

```bash
mailserver client-info --user user@example.com
```

Thunderbird autoconfig helper XML is served on the webmail host at:

```text
https://mail.example.com/mail/config-v1.1.xml
https://mail.example.com/.well-known/autoconfig/mail/config-v1.1.xml
```

Use this URL when Thunderbird automatic discovery does not find the account from
the email domain alone.

Apple Mail does not use Thunderbird's autoconfig XML. A passwordless Apple
configuration profile for the primary mailbox is served at:

```text
https://mail.example.com/mail/apple.mobileconfig
https://mail.example.com/.well-known/mail/apple.mobileconfig
```

The profile includes IMAP/SMTP host, port, TLS, and username settings only. The
mailbox password is still entered locally on the Apple device.

## Health Checks

Run the broad check suite:

```bash
sudo mailserver doctor
```

To repair safe local drift, such as UFW rules, stopped installed services, and
managed SOGo/nginx/autoconfig files that differ from templates, run:

```bash
sudo mailserver doctor --fix
```

Run a local end-to-end delivery test without sending external email:

```bash
sudo mailserver e2e-delivery --user user@example.com --password-file /etc/mailserver/secrets/user-password
```

The test injects a local message through Postfix, logs in over IMAPS, searches
and fetches the message from INBOX, verifies SOGo DAV with the mailbox password,
and removes the test message unless `--no-cleanup` is set.

Check whether live SOGo/webmail generated config files still match the repo
templates and current config values:

```bash
sudo mailserver config-drift
```

This command intentionally covers the generated SOGo nginx vhost, SOGo config,
and Thunderbird autoconfig XML. It is not a full drift audit for every Postfix,
Dovecot, DKIM, DMARC, Rspamd, Fail2ban, or SSH hardening file.

Inspect Rspamd controller state:

```bash
sudo mailserver rspamd-state
sudo mailserver rspamd-state counters
```

Check recommended TLS policy records:

```bash
mailserver tls-policy-state
mailserver tls-policy-state --domain example.com
```

Missing MTA-STS, SMTP TLS reporting, or DANE records are warnings by default.
They are recommended hardening steps, not required for a working personal mailserver.

## Sent Copies

Outbound messages submitted through SMTP submission are copied into the sender's
IMAP `Sent` folder on the server. Postfix applies a submission-only BCC through
`submission-cleanup`, sending a copy to `user+Sent@domain`; Dovecot LMTP and the
global before-Sieve script store that plus-addressed copy in `Sent`.

This setup intentionally does not use Postfix `home_mailbox`, because delivery
uses virtual mailboxes over Dovecot LMTP (`virtual_transport =
lmtp:unix:private/dovecot-lmtp`), not Postfix local delivery.

## Storage

Mail accounts, domains, aliases, and SOGo groupware tables are stored in PostgreSQL.
Configure served domains with `PRIMARY_DOMAIN`, `SECONDARY_DOMAINS`, or
`sudo mailserver domains add --domain example.net`.

SOGo provides webmail, contacts, calendars, CalDAV/CardDAV, and ActiveSync.
It uses Dovecot IMAP for mail access and Postfix submission for outbound mail.

## Backups

Backups are written to `BACKUP_DIR`, default `/var/backups/mailserver-data`, as compressed tar archives. The backup includes mail server configuration, Let's Encrypt data, SOGo configuration, virtual mailboxes under `VMAIL_ROOT`, and a PostgreSQL dump.

Retention is controlled by `BACKUP_RETENTION_DAYS`, default `14`. The cron schedule is controlled by `BACKUP_CRON_SCHEDULE`, default `17 3 * * *`.

Backups stay on the same machine by default. For production, copy them to separate storage.

Disaster-recovery drill:

1. Copy the backup archive to a clean host or staging directory.
2. Run `sudo mailserver restore --validate ARCHIVE`.
3. Run `sudo mailserver restore --extract ARCHIVE --target /root/mailserver-restore-review`.
4. Review `postgresql/*.sql`, `etc/`, and maildirs under the extracted tree.
5. Stop affected services before manually restoring production files.
6. Restore PostgreSQL with `psql` only after confirming the dump target database.
7. Restore maildirs with ownership preserved for `vmail:vmail`.
8. Run `sudo mailserver verify`, `sudo mailserver doctor`, and a client login test.
