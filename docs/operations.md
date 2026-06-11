# Operations

Create a mailbox:

```bash
sudo mailserver add-user --user user@example.com
```

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
sudo mailserver add-alias --source postmaster@example.com --dest admin@example.com
```

Change a password:

```bash
sudo mailserver change-password --user user@example.com
```

Create an on-demand backup:

```bash
sudo mailserver backup
```

Install the recurring backup cron job:

```bash
sudo mailserver install-backup-cron
```

Useful logs:

```bash
journalctl -u postfix
journalctl -u dovecot
journalctl -u radicale
journalctl -u rspamd
tail -f /var/log/mail.log
```

Webmail URL:

```text
https://mail.example.com/
```

Radicale CalDAV/CardDAV base URL:

```text
https://dav.example.com/user@example.com/
```

Print complete manual setup values for Apple Mail, Apple Calendar, Thunderbird
Mail, and Thunderbird Calendar:

```bash
mailserver client-info --user user@example.com
```

## Sent Copies

Outbound messages submitted through SMTP submission are copied into the sender's
IMAP `Sent` folder on the server. Postfix applies a submission-only BCC through
`submission-cleanup`, sending a copy to `user+Sent@domain`; Dovecot LMTP and the
global before-Sieve script store that plus-addressed copy in `Sent`.

This setup intentionally does not use Postfix `home_mailbox`, because delivery
uses virtual mailboxes over Dovecot LMTP (`virtual_transport =
lmtp:unix:private/dovecot-lmtp`), not Postfix local delivery.

## Storage

Mail accounts, domains, and aliases are stored in SQLite at `MAIL_DB_PATH`.

Roundcube stores its application data in `/var/lib/roundcube` and uses SQLite by default.

Radicale stores calendars and contacts as flat files under `/var/lib/radicale/collections`.

Roundcube is installed from a pinned upstream release because the Ubuntu 26.04 package is not currently compatible with PHP 8.5. The pinned version, source URL, and SHA-256 checksum are configured in `~/.email-server/config.env`.

Calendar and contact sync are provided by Radicale. Use native clients such as iPhone Calendar, macOS Calendar, Thunderbird Calendar, or DAVx5 with an Android calendar app.

## Backups

Backups are written to `BACKUP_DIR`, default `/var/backups/mailserver-data`, as compressed tar archives. The backup includes mail server configuration, Let's Encrypt data, Roundcube application data, Radicale collections, and virtual mailboxes under `VMAIL_ROOT`.

The backup script also creates consistent SQLite snapshots using SQLite's online `.backup` command. These are stored inside the archive under `sqlite/mail.sqlite` and `sqlite/roundcube.sqlite` when the corresponding databases exist.

Retention is controlled by `BACKUP_RETENTION_DAYS`, default `14`. The cron schedule is controlled by `BACKUP_CRON_SCHEDULE`, default `17 3 * * *`.

Backups stay on the same machine by default. For production, copy them to separate storage.
