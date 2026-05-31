# Operations

Create a mailbox:

```bash
sudo ./scripts/add-user.sh user@example.com
```

Create an alias:

```bash
sudo ./scripts/add-alias.sh postmaster@example.com admin@example.com
```

Change a password:

```bash
sudo ./scripts/change-password.sh user@example.com
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

Roundcube is installed from a pinned upstream release because the Ubuntu 26.04 package is not currently compatible with PHP 8.5. The pinned version, source URL, and SHA-256 checksum are configured in `mail.env`.

Calendar and contact sync are provided by Radicale. Use native clients such as iPhone Calendar, macOS Calendar, Thunderbird Calendar, or DAVx5 with an Android calendar app. A browser calendar UI is intentionally not installed by default.
