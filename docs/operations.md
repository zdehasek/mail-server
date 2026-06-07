# Operations

Create a mailbox:

```bash
sudo ./scripts/add-user.sh user@example.com
```

Create or refresh the configured primary mailbox and operational aliases:

```bash
sudo make setup-primary-mailbox
```

If the primary mailbox password was generated during setup, read it with:

```bash
sudo cat /etc/mailserver/secrets/primary-mailbox-password
```

Create an alias:

```bash
sudo ./scripts/add-alias.sh postmaster@example.com admin@example.com
```

Change a password:

```bash
sudo ./scripts/change-password.sh user@example.com
```

Create an on-demand backup:

```bash
sudo make backup
```

Install the recurring backup cron job:

```bash
sudo make install-backup-cron
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

## Storage

Mail accounts, domains, and aliases are stored in SQLite at `MAIL_DB_PATH`.

Roundcube stores its application data in `/var/lib/roundcube` and uses SQLite by default.

Radicale stores calendars and contacts as flat files under `/var/lib/radicale/collections`.

Roundcube's calendar UI is provided by the `texxasrulez/calendar` plugin. The
plugin stores small support tables in `/var/lib/roundcube/roundcube.sqlite`, but
the calendar objects themselves stay in Radicale through CalDAV.

Roundcube is installed from a pinned upstream release because the Ubuntu 26.04 package is not currently compatible with PHP 8.5. The pinned version, source URL, and SHA-256 checksum are configured in `.env`.

Calendar and contact sync are provided by Radicale. Use native clients such as iPhone Calendar, macOS Calendar, Thunderbird Calendar, or DAVx5 with an Android calendar app. Browser calendar access is available in Roundcube through the Calendar task, backed by the same Radicale CalDAV endpoint.

## Backups

Backups are written to `BACKUP_DIR`, default `/var/backups/mailserver-data`, as compressed tar archives. The backup includes mail server configuration, Let's Encrypt data, Roundcube application data, Radicale collections, and virtual mailboxes under `VMAIL_ROOT`.

The backup script also creates consistent SQLite snapshots using SQLite's online `.backup` command. These are stored inside the archive under `sqlite/mail.sqlite` and `sqlite/roundcube.sqlite` when the corresponding databases exist.

Retention is controlled by `BACKUP_RETENTION_DAYS`, default `14`. The cron schedule is controlled by `BACKUP_CRON_SCHEDULE`, default `17 3 * * *`.

Backups stay on the same machine by default. For production, copy them to separate storage.
